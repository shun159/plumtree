import Config

config :hyparview,
  contact_nodes: [
    :"node1@127.0.0.1",
    :"node2@127.0.0.1",
    :"node3@127.0.0.1"
  ]

config :plumtree,
  plumtree_data_dir: "data/"

config :logger,
  level: :debug,
  format: "\n$date $time [$level] $message"
