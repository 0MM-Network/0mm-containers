disable_mlock = true
ui=true

storage "raft" {
   path    = "./openbao/vault"
   node_id = "vault"
}

listener "tcp" {
  address     = "127.0.0.100:8100"
  tls_disable = "true"
}

seal "transit" {
  address = "http://127.0.0.100:8200"
  disable_renewal = "false"
  key_name = "autounseal"
  mount_path = "transit/"
  tls_skip_verify = "true"
}

api_addr = "http://127.0.0.100:8100"
cluster_addr = "https://127.0.0.100:8101"
