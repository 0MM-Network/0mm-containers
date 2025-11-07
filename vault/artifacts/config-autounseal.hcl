disable_mlock = false
ui=true

storage "raft" {
   path    = "/vault/file"
   node_id = "vault"
}

listener "tcp" {
  address     = "0.0.0.0:8100"
  tls_disable = "true"
}

seal "transit" {
  address = "ADDRESS_PLACEHOLDER"
  disable_renewal = "false"
  key_name = "autounseal"
  mount_path = "transit/"
  tls_skip_verify = "true"
  token = "env://TRANSIT_TOKEN"
}

api_addr = "http://127.0.0.100:8100"
cluster_addr = "https://127.0.0.100:8101"
