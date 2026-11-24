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


railsctl_init() {
  local mode="${1:-required}"
  shift || true

  railsctl_load_global

  case "${mode}" in
    required)
      if [[ $# -ne 1 ]]; then
        railsctl_die "Expected exactly 1 argument (<service>), got $#."
      fi
      railsctl_load_service "$1"
      ;;
    optional)
      if [[ $# -gt 1 ]]; then
        railsctl_die "Expected at most 1 argument ([service]), got $#."
      fi
      if [[ $# -eq 1 ]]; then
        railsctl_load_service "$1"
      fi
      ;;
    *)
      railsctl_die "Internal error: unknown railsctl_init mode '${mode}'."
      ;;
  esac
}


###############################################################################
# Health-check polling helper (shared by start, resume, deploy)
###############################################################################
railsctl_wait_for_health() {
  local timeout="${HEALTH_TIMEOUT:-${DEFAULT_HEALTH_TIMEOUT:-15}}"
  local interval="${HEALTH_INTERVAL:-${DEFAULT_HEALTH_INTERVAL:-1}}"
  local journal_lines="${DEFAULT_JOURNAL_LINES:-40}"
  local url="${BIND_URL}${HEALTH_PATH}"
  local elapsed=0
  local code="000"

  railsctl_info "Waiting for health check ${url} (expecting HTTP ${HEALTH_EXPECTED_CODE}, timeout ${timeout}s)..."

  while (( elapsed < timeout )); do
    if ! systemctl is-active --quiet "${UNIT_NAME}"; then
      railsctl_err "${UNIT_NAME} is not active while waiting for health check."
      sudo journalctl -u "${UNIT_NAME}" -n "${journal_lines}" --no-pager >&2 || true
      return 1
    fi

    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "${url}" 2>/dev/null || true)"
    code="${code:-000}"
    if [[ "${code}" == "${HEALTH_EXPECTED_CODE}" ]]; then
      railsctl_info "Health check passed: HTTP ${code} (${url})"
      return 0
    fi

    sleep "${interval}"
    elapsed=$(( elapsed + interval ))
  done

  railsctl_err "Health check timed out after ${timeout}s (last HTTP ${code} from ${url})."
  sudo journalctl -u "${UNIT_NAME}" -n "${journal_lines}" --no-pager >&2 || true
  return 1
}

###############################################################################
# Reusable CLI boolean flag parser
# Usage: railsctl_parse_args --flag-one --flag-two -- "$@"
# Sets OPT_FLAG_ONE=true, OPT_FLAG_TWO=true for matched flags.
###############################################################################
railsctl_parse_args() {
  local allowed_flags=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      break
    fi
    allowed_flags+=("$1")
    shift
  done

  local arg allowed valid var_name
  for arg in "$@"; do
    valid=false
    for allowed in "${allowed_flags[@]}"; do
      if [[ "${arg}" == "${allowed}" ]]; then
        valid=true
        break
      fi
    done

    if [[ "${valid}" != "true" ]]; then
      railsctl_die "Unknown option '${arg}'. Supported flags: ${allowed_flags[*]}"
    fi

    var_name="OPT_${arg#--}"
    var_name="${var_name//-/_}"
    var_name="${var_name^^}"
    # local assignment follows
    printf -v "${var_name}" '%s' "true"
  done
}

