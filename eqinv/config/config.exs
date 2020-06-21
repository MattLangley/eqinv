use Mix.Config

config :pooler, pools:
  [
    [
      name: :riaklocal1,
      group: :riak,
      max_count: 15,
      init_count: 2,
      start_mfa: { Riak.Connection, :start_link, ['eqinv-riak-kv', 8087] }
    ]
  ]