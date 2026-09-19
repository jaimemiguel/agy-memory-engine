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
if [ -f "${LOG}" ]; then
    tail -n 1000 "${LOG}" > "${LOG}.tmp" && cat "${LOG}.tmp" > "${LOG}" && rm -f "${LOG}.tmp"
fi

HOSTNAME_LABEL="$(scutil --get HostName 2>/dev/null || hostname -s)"

# ------------------------------------------------------------------------------
# 3. Calm Worker Execution
# ------------------------------------------------------------------------------
if [ -x "${PYTHON_BIN}" ]; then
    # Run the worker; only log when work was performed or errors occurred
    OUTPUT="$("${PYTHON_BIN}" "${SCRIPT_DIR}/memory_worker.py" 2>&1)" || {
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
