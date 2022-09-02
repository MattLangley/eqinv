defmodule EQInv do
    @moduledoc """
    Documentation for Eqinv.
    """

    require Logger
    use Bitwise

    # Constants
    @bucket "EQINV"
    @headerKey "HDR"
    @invKey "INV"

    @invIdx %{
        "id" => 2,
        "count" => 3
    }

    @dataIdx %{
        "id" => 5,
        "count" => 6,
        "slots" => 11,
        "name" => 1,
        "classes" => 36,
        "recLevel" => 50,
        "reqLevel" => 49,
        "damage" => 62,
        "delay" => 58,
        "type" => 68,
        "int" => 27,
        "wis" => 28,
        "str" => 22,
        "sta" => 23,
        "agi" => 24,
        "dex" => 25,
        "ac" => 32,
        "haste" => 126,
        "hp" => 29,
        "mana" => 30
    }

    @slots %{
        "Pri" => 8192,
        "Sec" => 16384,
        "PriSec" => 24576,
        "Back" => 256,
        "Feet" => 524288,
        "Wrist" => 1536,
        "Chest" => 131072,
        "Hands" => 4096,
        "Legs" => 262144,
        "Head" => 4,
        "Arms" => 128,
        "Shoulders" => 64,
        "Finger" => 98304,
        "Ear" => 18,
        "Range" => 2048,
        "Face" => 8,
        "Waist" => 1048576,
        "Neck" => 32
    }

    @itemType %{
        -1 => "-1",
        "1hb" => "3",
        "1hs" => "0",
        "1hp" => "2",
        "2hs" => "1",
        "2hp" => "35",
        "2hb" => "4",
        "hth" => "45",
        "Armor" => "10",
        "Hands" => "4096"
    }

    @classes %{
        "War" => 1,
        "Cle" => 2,
        "Pal" => 4,
        "Ran" => 8,
        "Shm" => 16,
        "Dru" => 32,
        "Mon" => 64,
        "Bar" => 128,
        "Rog" => 256,
        "Sha" => 512,
        "Nec" => 1024,
        "Wiz" => 2048,
        "Mag" => 4096,
        "Enc" => 8192,
        "Bea" => 16384,
        "Ber" => 32768
    }

    def fieldI(data, key), do: field(data, key) |> toInt
    def field(data, key), do: Enum.at(data, @dataIdx[key])

    def toInt(nil), do: "-1"
    def toInt(""), do: "-1"
    def toInt(value), do: String.to_integer(value)

    def findClassOnly(slot, class, isRec, reqLevel) do
        classNum = @classes[class]
        findItems(slot, class, isRec, reqLevel, fn data ->
            itemClass = fieldI(data, "classes")
            # Logger.debug("item data: #{inspect data}")
            itemClass == classNum
        end) |>
        Enum.map(fn item ->
            statBlock(item)
        end)
    end

    # EQInv.findWeaponDmgDly("Pri", "Pal", false, 0, "2hs")
    # EQInv.findWeaponDmgDly("Pri", "Ran", false, 0, "2hs")
    def findWeaponDmgDly(slot, class, isRec, reqLevel, type \\ -1) do
        items =
        findItems(slot, class, isRec, reqLevel, fn data ->
            damage = fieldI(data, "damage")
            # Logger.debug("item data: #{inspect data}")
            if 0 != damage do
                itemType = fieldI(data, "type")
                typeNum = @itemType[type] |> String.to_integer
                -1 == type || itemType == typeNum
            else
                false
            end
        end)

        Enum.sort(items, fn a,b ->
            aData = a["data"]
            bData = b["data"]
            aDamage = fieldI(aData, "damage")
            aDelay = fieldI(aData, "delay")
            bDamage = fieldI(bData, "damage")
            bDelay = fieldI(bData, "delay")

            aRatio = aDamage / aDelay
            bRatio = bDamage / bDelay

            aRatio < bRatio
        end) |>
        Enum.map(fn item ->
            data = item["data"]
            damage = fieldI(data, "damage")
            delay = fieldI(data, "delay")
            statBlock(item) |> Map.put("damage_delay", damage / delay)
        end)
    end

    def headerIdx(name) do
        headers = get(@bucket, @headerKey)
        Enum.find_index(headers, fn v -> v == name end)
    end

    # EQInv.findArmorStat("Pri", "Wiz", false, 0, "int")
    # EQInv.findArmorStat("Head", "Pal", false, -1, "ac")
    # EQInv.findArmorStat("Head", "Ran", false, 0, "ac")
    # EQInv.findArmorStat("Neck", "Ran", false, 0, ["ac", "wis", "str"])
    def findArmorStat(slot, class, isRec, reqLevel, statName, type \\ -1) do
        items =
        findItems(slot, class, isRec, reqLevel, fn data ->
            itemType = fieldI(data, "type")
            typeNum = @itemType[type] |> String.to_integer
            if -1 == type || itemType == typeNum do
                statCheck(data, statName)
            else
                false
            end
        end)

        Enum.sort(items, fn a, b ->
            aData = a["data"]
            bData = b["data"]
            # Logger.debug("a: #{inspect a}")
            # Logger.debug("b: #{inspect b}")
            aStat = statScore(aData, statName)
            bStat = statScore(bData, statName)

            aStat < bStat
        end) |>
        Enum.map(fn item ->
            data = item["data"]
            statScore = statScore(data, statName)
            # count = length(item["locs"])
            # name = field(data, "name")
            # req = fieldI(data, "reqLevel")
            # rec = fieldI(data, "recLevel")
            # block =
            # %{
            #     "name" => name,
            #     "count" => count,
            #     "req" => req,
            #     "rec" => rec
            # }
            block = statBlock(item)
            findStats = %{}
            findStats = Map.put(findStats, "statScore", statScore)
            findStats = addStats(data, findStats, statName)
            Map.put(block, "findStats", findStats)
        end)
    end

    def statCheck(data, stats) when not is_list(stats), do: statCheck(data, [stats])

    def statCheck(_data, []), do: false
    def statCheck(data, [statName | stats]) do
        stat = fieldI(data, statName)
        if 0 < stat do
            true
        else
            statCheck(data, stats)
        end
    end

    def statScore(data, stats) when not is_list(stats), do: statScore(data, [stats])
    def statScore(data, stats), do: statScore(data, stats, 0)

    def statScore(_data, [], score), do: score
    def statScore(data, [statName | stats], score) do
        score = fieldI(data, statName) + score
        statScore(data, stats, score)
    end

    def invCount() do
        items = get(@bucket, @invKey)
        Enum.reduce(items, 0, fn {_id, item}, acc ->
            count = item["locs"] |> length
            acc + count
        end)
    end

    def searchInvName(name) do
        items = get(@bucket, @invKey)
        items = Enum.reduce(items, [], fn {_id, item}, acc ->
            data = item["data"]
            if data do
                itemName = field(data, "name")
                {:ok, search} = Regex.compile(String.downcase(name))
                if String.match?(String.downcase(itemName), search) do
                    [statBlock(item) | acc]
                else
                    acc
                end
            else
                acc
            end
        end)

        {items, length(items)}
    end

    # EQInv.findInvName("Deepwater Helmet")
    def findInvName(name) do
        items = get(@bucket, @invKey)
        {_id, item} = Enum.find(items, fn {_id, item} ->
            # Logger.debug("item: #{inspect item}")
            data = item["data"]
            if data do
                itemName = field(data, "name")
                itemName == name
            else
                false
            end
        end)
        # Logger.debug("item: #{inspect item}")

        if item do
            statBlock(item)
        else
            Logger.debug("item not found: #{name}")
        end
    end

    def statBlock(item) do
        # Logger.debug("item: #{inspect item}")
        data = item["data"]
        name = field(data, "name")
        stats = [
            "str",
            "wis",
            "int",
            "sta",
            "dex",
            "agi",
            "ac",
            "damage",
            "delay",
            "recLevel",
            "reqLevel",
            "haste"
        ]
        locs = item["locs"]
        {count, locs} = statBlockLocs(locs)
        block =
        %{
            "name" => name,
            "count" => count,
            "locs" => locs
        }

        addStats(data, block, stats)
    end

    # EQInv.searchInvName("Fulginate Ore")
    def statBlockLocs(locs), do: statBlockLocs(locs, {0, []})

    def statBlockLocs([], acc), do: acc
    def statBlockLocs([loc | locs], {count, acc}) do
        name = Enum.at(loc, 0)
        type = Enum.at(loc, 1)
        id = case type do
            :realestate ->
                id1 = Enum.at(loc, 2)
                id2 = Enum.at(loc, 3)
                "#{id1}_#{id2}"
            :inventory ->
                Enum.at(loc, 2)
        end
        c = case type do
            :realestate -> Enum.at(loc, @dataIdx["count"] + 2) |> String.replace("\n", "") |> String.to_integer()
            :inventory -> Enum.at(loc, @invIdx["count"] + 2) |> String.replace("\n", "") |> String.to_integer()
        end
        locBlock = %{
            "name" => name,
            "type" => type,
            "id" => id,
            "count" => c
        }
        acc = [locBlock | acc]
        statBlockLocs(locs, {count + c, acc})
    end

    def addStats(data, block, stats) when not is_list(stats), do: addStats(data, block, [stats])
    def addStats(_data, block, []), do: block
    def addStats(data, block, [statName | stats]) do
        stat = fieldI(data, statName)
        block =
        if 0 != stat do
            Map.put(block, statName, stat)
        else
            block
        end
        addStats(data, block, stats)
    end

    # EQInv.findArmorStat("Head", "Pal", true, -1, "ac")
    # EQInv.findArmorStat("Face", "Ran", false, 0, ["ac", "wis", "str"])
    def findItems(slot, class, isRec, reqLevel, check) do
        items = get(@bucket, @invKey)
        if -1 != slot && !Map.has_key?(@slots, slot) do
            Logger.debug("invalid slot: #{slot}")
            []
        else
            Enum.reduce(items, [], fn {_id, item}, acc ->
                # Logger.debug("reduce id: #{inspect id} item: #{inspect item}")
                data = item["data"]
                if data do
                    # Logger.debug("hasData")
                    # name = field(data, "name")
                    # Logger.debug("findItems name: #{inspect name}")
                    slots = fieldI(data, "slots")
                    if slotsCheck(slots, slot) do
                        classes = fieldI(data, "classes")
                        if classCheck(classes, class) do
                            itemRecLevel = fieldI(data, "recLevel")
                            itemReqLevel = fieldI(data, "reqLevel")
                            # Logger.debug("itemRecLevel: #{itemRecLevel} itemReqLevel: #{itemReqLevel}")
                            # recCheckRes = recCheck(itemRecLevel, isRec)
                            # Logger.debug("recCheckRes: #{inspect recCheckRes}")
                            if recCheck(itemRecLevel, isRec) && reqCheck(itemReqLevel, reqLevel) do
                                if check.(data) do
                                    acc = [item | acc]
                                    acc
                                else
                                    acc
                                end
                            else
                                # Logger.debug("recreqCheck failed")
                                acc
                            end
                        else
                            # Logger.debug("classCheck failed")
                            acc
                        end
                    else
                        # Logger.debug("slotsCheck failed")
                        acc
                    end
                else
                    # Logger.debug("doesn't have data")
                    acc
                end
            end)
        end
    end

    def recCheck(_itemRecLevel, true), do: true
    def recCheck(itemRecLevel, isRec) do
        ((itemRecLevel > 0) && isRec) || ((itemRecLevel == 0) && !isRec)
    end

    def reqCheck(_, -1), do: true
    def reqCheck(itemReqLevel, reqLevel) do
        reqLevel >= itemReqLevel
    end

    def classCheck(classes, class) do
        classNum = @classes[class]
        classNum == (classes &&& classNum)
    end

    def slotsCheck(_slots, -1), do: true

    def slotsCheck(slots, slot) do
        slotNum = @slots[slot]
        # Logger.debug("slotNum: #{inspect slotNum} slots: #{inspect slots}")
        slotNum == (slots &&& slotNum)
    end

    def loadInv() do
        privPath = :code.priv_dir(:eqinv)
        loadInvPath = "#{privPath}/inv"
        {:ok, files} = File.ls(loadInvPath)

        items = %{}

        items =
        Enum.reduce(files, items, fn file, acc ->
            acc =
            if !File.dir?(file) && ".txt" == Path.extname(file) do
                Logger.debug("file: #{file}")
                fullPath = "#{loadInvPath}/#{file}"
                type =
                if String.ends_with?(file, "RealEstate.txt") do
                    :realestate
                else if String.ends_with?(file, "Inventory.txt") do
                    :inventory
                else
                    nil
                end end

                name = Path.rootname(file)

                if nil != type do
                    Logger.debug("opening file fullPath: #{fullPath}")
                    {:ok, acc} =
                    File.open(fullPath, [:read], fn file ->
                        handleInvLine(acc, :headers, name, type, file, IO.read(file, :line))
                    end)
                    Logger.debug("done with file fullPath: #{fullPath}")
                    acc
                else
                    Logger.debug("type unknown: #{file}")
                    acc
                end
            else
                acc
            end

            acc
        end)

        # Logger.debug("items: #{inspect items}")
        put(@bucket, @invKey, items)
    end

    def handleInvLine(items, _, _, _, _, :eof) do
        Logger.debug("inv file done")
        items
    end

    def handleInvLine(items, :headers, name, type, file, _line) do
        handleInvLine(items, :body, name, type, file, IO.read(file, :line))
    end

    def handleInvLine(items, :body, name, type, file, line) do
        entryVals = String.split(line, "\t")
        # Logger.debug("handleInvLine : #{inspect entryVals}")
        id = invFieldI(type, entryVals, "id")
        if "-1" == id do
            Logger.debug("id: #{inspect id}")
            Logger.debug("entryVals: #{inspect entryVals} id: #{inspect id}")
        end
        data = get(@bucket, id)
        vals =
        Map.get(items, id, %{"locs" => [], "data" => nil}) |>
        Map.put("data", data)

        entryVals = [type | entryVals]
        entryVals = [name | entryVals]
        locs = Map.get(vals, "locs")
        locs = [entryVals | locs]

        vals = Map.put(vals, "locs", locs)
        items = Map.put(items, id, vals)
        # Logger.debug("handleInvLine calling handleInvLine")
        handleInvLine(items, :body, name, type, file, IO.read(file, :line))
    end

    def invFieldI(:inventory, entryVals, "id"), do: Enum.at(entryVals, @invIdx["id"]) |> String.to_integer
    def invFieldI(_, entryVals, key), do: fieldI(entryVals, key)

    def loadItems() do
        privPath = :code.priv_dir(:eqinv)
        itemsPath = "#{privPath}/items/items.txt"
        File.open(itemsPath, [:read], fn file ->
            handleItemLine(:headers, file, IO.read(file, :line))
        end)

        itemsPath = "#{privPath}/items/items2.txt"
        File.open(itemsPath, [:read], fn file ->
            handleItemLine(:body, file, IO.read(file, :line))
        end)

        itemsPath = "#{privPath}/items/items3.txt"
        File.open(itemsPath, [:read], fn file ->
            handleItemLine(:body, file, IO.read(file, :line))
        end)
    end

    def handleItemLine(_, _, :eof) do
        Logger.debug("file loading done")
    end

    def handleItemLine(:headers, file, line) do
        Logger.debug("headers line: #{line}")
        headerVals = String.split(line, "|")
        Logger.debug("headerVals: #{inspect headerVals}")
        put(@bucket, @headerKey, headerVals)
        handleItemLine(:body, file, IO.read(file, :line))
    end

    def handleItemLine(:body, file, line) do
        # Logger.debug("line: #{line}")
        entryVals = String.split(line, "|")
        # Logger.debug("entryVals: #{inspect entryVals}")
        id = fieldI(entryVals, "id")
        # Logger.debug("id: #{inspect id}")
        put(@bucket, id, entryVals)
        handleItemLine(:body, file, IO.read(file, :line))
    end

    def put(bucket, key, value) do
        key = :erlang.term_to_binary(key)
        o = Riak.Object.create(bucket: bucket, key: key, data: value)
        Riak.put(o)
    end

    def get(bucket, key) do
        # if !handleGet(@bucket, @invKey) do
        #     Logger.debug("get is false")
        # end

        # getResp = handleGet(@bucket, @invKey)
        # # Logger.debug("getResp: #{inspect getResp}")

        handleGet(bucket, key)
    end

    defp handleGet(bucket, key) do
        key = :erlang.term_to_binary(key)
        o = Riak.find(bucket, key)

        if nil != o do
            o.data |> :erlang.binary_to_term
        else
            nil
        end
    end
end
