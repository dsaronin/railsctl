# bin/railsctl.d/_common.sh
# Shared helper library for railsctl subcommands

set -euo pipefail

# Resolve RAILSCTL_ROOT relative to this file if not already exported by dispatcher
if [[ -z "${RAILSCTL_ROOT:-}" ]]; then
  _COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  RAILSCTL_ROOT="$(cd "${_COMMON_DIR}/../.." && pwd)"
  export RAILSCTL_ROOT
fi

###############################################################################
# ANSI-color-wrapped output functions
###############################################################################
railsctl_info() {
  echo -e "[railsctl] $*"
}

railsctl_alert() {
  echo -e '\E[1;34m'"[railsctl] $*"'\E[1m\E[0m'
}

railsctl_warn() {
  echo -e '\E[1;32m'"[railsctl] WARN: $*"'\E[1m\E[0m'
}

railsctl_status() {
  echo -e '\E[1;33m'"[railsctl] $*"'\E[1m\E[0m'
}

railsctl_err() {
  echo -e '\E[1;31m'"[railsctl] ERROR: $*"'\E[1m\E[0m' >&2
}

railsctl_die() {
  railsctl_err "$*"
  exit 1
}

###############################################################################
# Configuration & logging helpers
###############################################################################
railsctl_load_global() {
  local global_conf="${RAILSCTL_ROOT}/.config/railsctl.conf"
  [[ -f "${global_conf}" ]] || railsctl_die "Missing global config: ${global_conf}"
  # shellcheck source=/dev/null
  source "${global_conf}"
}

railsctl_list_services() {
  local conf_dir="${RAILSCTL_CONFIG_DIR:-${RAILSCTL_ROOT}/.config}"
  local file base
  for file in "${conf_dir}"/*.conf; do
    [[ -e "${file}" ]] || continue
    base="$(basename "${file}" .conf)"
    [[ "${base}" == "railsctl" ]] && continue
    printf '%s\n' "${base}"
  done
}

railsctl_load_service() {
  local service="${1:-}"
  [[ -n "${service}" ]] || railsctl_die "Service name required."

  if [[ ! "${service}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    railsctl_die "Invalid service name: '${service}'"
  fi

  local service_conf="${RAILSCTL_CONFIG_DIR}/${service}.conf"
  if [[ ! -f "${service_conf}" ]]; then
    local available
    available="$(railsctl_list_services | paste -sd ', ' -)"
    railsctl_die "Unknown service '${service}'. Configured services: ${available:-none}"
  fi

  # shellcheck source=/dev/null
  source "${service_conf}"
}

railsctl_log() {
  local action="${1:-EVENT}"
  shift || true
  local message="$*"

  [[ -n "${SERVICE_NAME:-}" ]] || return 0
  local log_dir="${RAILSCTL_SERVICES_DIR}/${SERVICE_NAME}"
  mkdir -p "${log_dir}"

  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  printf '%s | %-8s | %s\n' "${ts}" "${action}" "${message}" >> "${log_dir}/railsctl.log"
}
