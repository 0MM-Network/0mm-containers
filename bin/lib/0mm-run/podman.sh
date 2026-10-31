# Podman backend for bin/0mm-run. Sourced after the dispatcher has validated
# the manifest (M), the cache mounts (VOLUMES), and the arguments.
# The fixed flags below are the frozen hardening floor in ADR 0002.

backend_exec() {
  local argv=(run --rm
    --userns=keep-id
    --cap-drop=all
    --security-opt=no-new-privileges
    --read-only
    "--network=${M[network]:-none}"
    "--pids-limit=${M[pids_limit]:-1024}"
    "--memory=${M[memory]:-4g}"
    "--cpus=${M[cpus]:-2}")
  local item cmd=()
  while IFS= read -r item; do argv+=("--env=${item}"); done < <(elems env)
  for item in "${VOLUMES[@]+"${VOLUMES[@]}"}"; do argv+=("--volume=${item}"); done
  mapfile -t cmd < <(elems command)
  argv+=("--volume=${PWD}:/work" --workdir=/work "${M[image]}" "${cmd[@]}" "$@")
  exec podman "${argv[@]}"
}
