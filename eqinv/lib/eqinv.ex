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
    
    @dataIdx %{
        "id" => 5,
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
        "Range" => 2048
    }

    @itemType %{
        -1 => "-1",
        "1hb" => "3",
        "1hs" => "0",
        "1hp" => "2",
        "2hs" => "1",
        "2hp" => "35",
        "2hb" => "4",
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

    def fieldI(data, key), do: field(data, key) |> String.to_integer
    def field(data, key), do: Enum.at(data, @dataIdx[key])

    # EQInv.findWeaponDmgDly("Pri", "Pal", false, 0, "2hs")
    def findWeaponDmgDly(slot, class, isRec, reqLevel, type \\ -1) do
        items = 
        findItems(slot, class, isRec, reqLevel, fn data ->
            damage = fieldI(data, "damage")
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
            name = field(data, "name")
            damage =fieldI(data, "damage")
            delay = fieldI(data, "delay")
            %{
                "name" => name,
                "damage" => damage,
                "delay" => delay,
                "ratio" => damage / delay
            }
        end)
    end

    # EQInv.findArmorStat("Pri", "Wiz", false, 0, "int")
    # EQInv.findArmorStat("Head", "Pal", false, -1, "ac")
    def findArmorStat(slot, class, isRec, reqLevel, statName, type \\ -1) do
        items = 
        findItems(slot, class, isRec, reqLevel, fn data ->
            itemType = fieldI(data, "type")
            typeNum = @itemType[type] |> String.to_integer
            if -1 == type || itemType == typeNum do
                stat = fieldI(data, statName)
                # Logger.debug("data: #{inspect data}")
                # Logger.debug("stat: #{inspect stat}")
                0 < stat
            else
                false
            end
        end)

        Enum.sort(items, fn a,b ->
            aData = a["data"]
            bData = b["data"]
            aStat = fieldI(aData, statName)
            bStat = fieldI(bData, statName)

            aStat < bStat
        end) |>
        Enum.map(fn item -> 
            data = item["data"]
            count = length(item["locs"])
            name = field(data, "name")
            stat = fieldI(data, statName)
            req = fieldI(data, "reqLevel")
            rec = fieldI(data, "recLevel")
            block =
            %{
                "name" => name,
                "count" => count,
                "req" => req,
                "rec" => rec
            }
            Map.put(block, statName, stat)
        end)
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
        Logger.debug("item: #{inspect item}")
        
        if item do
            statBlock(item)
        else
            Logger.debug("item not found: #{name}")
        end
    end

    def statBlock(item) do
        Logger.debug("item: #{inspect item}")
        count = length(item["locs"])
        data = item["data"]
        name = field(data, "name")
        stats = [
            "str",
            "wis",
            "int",
            "ac",
            "damage",
            "delay",
            "recLevel",
            "reqLevel"
        ]
        block =
        %{
            "name" => name,
            "count" => count
        }

        addStats(data, block, stats)
    end

    def addStats(_data, block, []), do: block
    def addStats(data, block, [statName | stats]) do
        stat = fieldI(data, statName)
        block = Map.put(block, statName, stat)
        addStats(data, block, stats)
    end

    # EQInv.findArmorStat("Head", "Pal", true, -1, "ac")
    def findItems(slot, class, isRec, reqLevel, check) do
        items = get(@bucket, @invKey)
        items = Enum.reduce(items, [], fn {_id, item}, acc ->
            data = item["data"]
            if data do
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
                acc
            end
        end)
        items
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

    def slotsCheck(slots, slot) do
        slotNum = @slots[slot]
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
                # Logger.debug("file: #{file}")
                fullPath = "#{loadInvPath}/#{file}"
                {:ok, acc} =
                File.open(fullPath, [:read], fn file ->
                    handleInvLine(acc, :headers, file, IO.read(file, :line))
                end)
                acc
            else
                acc
            end

            acc
        end)

        # Logger.debug("items: #{inspect items}")
        put(@bucket, @invKey, items)
    end

    def handleInvLine(items, _, _, :eof) do
        Logger.debug("inv file done")
        items
    end

    def handleInvLine(items, :headers, file, _line) do
        handleInvLine(items, :body, file, IO.read(file, :line))
    end

    def handleInvLine(items, :body, file, line) do
        entryVals = String.split(line, "\t")
        # Logger.debug("entryVals: #{inspect entryVals}")
        id = fieldI(entryVals, "id")
        Logger.debug("id: #{inspect id}")
        # Logger.debug("items: #{inspect items} id: #{inspect id}")
        data = get(@bucket, id)
        vals = 
        Map.get(items, id, %{"locs" => [], "data" => nil}) |>
        Map.put("data", data)

        locs = Map.get(vals, "locs")
        locs = [entryVals | locs]

        vals = Map.put(vals, "locs", locs)
        items = Map.put(items, id, vals)
        handleInvLine(items, :body, file, IO.read(file, :line))
    end

    def loadItems() do
        privPath = :code.priv_dir(:eqinv)
        itemsPath = "#{privPath}/items/items.txt"
        File.open(itemsPath, [:read], fn file ->
            handleItemLine(:headers, file, IO.read(file, :line))
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
        key = :erlang.term_to_binary(key)
        o = Riak.find(bucket, key)

        if nil != o do
            o.data |> :erlang.binary_to_term
        else
            nil
        end
    end
end
