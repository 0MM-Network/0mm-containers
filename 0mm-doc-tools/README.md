# 0mm-doc-tools

Generic document and text tool runtime for rootless Podman.

```bash
./build.sh
# -> localhost/0mm-doc-tools:local
podman run --rm localhost/0mm-doc-tools:local tools-versions
```

Mounts (host-owned): `/config` (ro), `/pipeline` (ro), `/work` (rw).  
The image ships binaries only. Pipeline scripts and rule packs stay on the host.
