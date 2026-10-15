#!/usr/bin/env bash
# Install private-subrepo helper + optional Salt formula under BTSTRP_ROOT/bin/lib/.
# Does not clone; does not run salt-apply. Principal runs the shell helper (or Salt later).
set -euo pipefail
: "${BTSTRP_ROOT:?BTSTRP_ROOT required}"
: "${PACKAGE_DIR:?PACKAGE_DIR required}"

mkdir -p "${BTSTRP_ROOT}/bin/lib/salt"

src_lib="${PACKAGE_DIR}/bin/lib/bootstrap_private_subrepo"
src_shim="${PACKAGE_DIR}/bin/bootstrap_private_subrepo"
src_sls="${PACKAGE_DIR}/bin/lib/salt/bootstrap_private_subrepo.sls"

[[ -f "$src_lib" ]] || { echo "0060: missing $src_lib" >&2; exit 1; }
install -m 0755 "$src_lib" "${BTSTRP_ROOT}/bin/lib/bootstrap_private_subrepo"

if [[ -f "$src_shim" ]]; then
  install -m 0755 "$src_shim" "${BTSTRP_ROOT}/bin/bootstrap_private_subrepo"
else
  cat >"${BTSTRP_ROOT}/bin/bootstrap_private_subrepo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
exec "${HERE}/lib/bootstrap_private_subrepo" "$@"
SH
  chmod 0755 "${BTSTRP_ROOT}/bin/bootstrap_private_subrepo"
fi

if [[ -f "$src_sls" ]]; then
  install -m 0644 "$src_sls" "${BTSTRP_ROOT}/bin/lib/salt/bootstrap_private_subrepo.sls"
fi

echo "0060-bootstrap-private-subrepo: installed bin/lib/bootstrap_private_subrepo, bin/ shim, bin/lib/salt/*.sls"
