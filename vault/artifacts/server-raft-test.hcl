# Neutral test-server config template (no host VIP).
# Runtime vault0-test-server.sh renders concrete paths/ports into state dir.
ui = false
disable_mlock = true

storage "raft" {
  path    = "/vault/file"
  node_id = "vault0-test"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}

api_addr     = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
