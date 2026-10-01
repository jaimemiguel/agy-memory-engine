#!/usr/bin/env bash
# ==============================================================================
# AGY Memory Engine — Automated Calm Cron Runner
# ==============================================================================
# NOTE: Executed via crontab (e.g. */5 * * * *)
#
# Architectural Responsibilities:
# 1. PATH Setup: Cron runs in a minimal macOS environment (/usr/bin:/bin).
#    Ensures Homebrew, local user bin, and Python virtual environment are reachable.
# 2. Log Safety: Enforces mandatory startup trimming of the worker cron log to the last
#    1,000 lines to prevent unbounded disk growth.
# 3. Execution: Invokes the debounced calm worker using the project's dedicated .venv.
# ==============================================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="/Volumes/Extern2TB/GitHub/_Logs/agy-memory-engine"
LOG="${LOG_DIR}/memory_worker_cron.log"
PYTHON_BIN="${SCRIPT_DIR}/.venv/bin/python"

# Ensure target log directory exists
mkdir -p "${LOG_DIR}"

# ------------------------------------------------------------------------------
# 1. Environment & PATH Resolution for Cron
# ------------------------------------------------------------------------------
export HOME="${HOME:-/Users/jmb}"
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export PATH="${HOME}/.local/bin:${HOME}/bin:$PATH"

# Load environment configuration if available
if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a
    source "${SCRIPT_DIR}/.env"
    set +a
fi

# ------------------------------------------------------------------------------
# 2. Mandatory Log Management & Trimming (Last 1,000 Lines)
# ------------------------------------------------------------------------------
for l in "${LOG}" "${LOG_DIR}/launchagent_out.log" "${LOG_DIR}/launchagent_err.log"; do
    if [ -f "${l}" ]; then
        tail -n 1000 "${l}" > "${l}.tmp" && cat "${l}.tmp" > "${l}" && rm -f "${l}.tmp"
    fi
done

HOSTNAME_LABEL="$(scutil --get HostName 2>/dev/null || hostname -s)"
CURRENT_UID="$(id -u 2>/dev/null || echo "${UID:-501}")"

# ------------------------------------------------------------------------------
# 3. Calm Worker Execution
# ------------------------------------------------------------------------------
if [ -x "${PYTHON_BIN}" ]; then
    # When running on macOS, ensure execution occurs within user Aqua session context
    # so Keychain API calls (for CLI silent auth) succeed without headless blocks.
    if [[ "$(uname)" == "Darwin" ]] && command -v launchctl >/dev/null 2>&1 && [ -n "${CURRENT_UID}" ] && [ "${CURRENT_UID}" -ge 500 ]; then
        RUNNER_CMD=(launchctl asuser "${CURRENT_UID}" "${PYTHON_BIN}" "${SCRIPT_DIR}/memory_worker.py")
    else
        RUNNER_CMD=("${PYTHON_BIN}" "${SCRIPT_DIR}/memory_worker.py")
    fi

    OUTPUT="$("${RUNNER_CMD[@]}" 2>&1)" || {
        STATUS=$?
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${HOSTNAME_LABEL}] [ERROR] Memory worker exited with code ${STATUS}: ${OUTPUT}" >> "${LOG}"
        exit ${STATUS}
    }
    if [ -n "${OUTPUT}" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${HOSTNAME_LABEL}] [INFO] ${OUTPUT}" >> "${LOG}"
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${HOSTNAME_LABEL}] [ERROR] Python virtualenv not found at ${PYTHON_BIN}" >> "${LOG}"
    exit 1
fi
