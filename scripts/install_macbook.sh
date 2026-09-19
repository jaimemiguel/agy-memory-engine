#!/usr/bin/env bash
# ==============================================================================
# AGY Memory Engine — MacBook Pro / Air Setup Script
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${1:-$SCRIPT_DIR}"
STORAGE_ROOT="/Volumes/Extern2TB/agy-memory"

echo "========================================================================"
echo "⚡ Setting up AGY Memory Engine on macOS"
echo "   Project Root: ${TARGET_DIR}"
echo "   Storage Root: ${STORAGE_ROOT}"
echo "========================================================================"

# 1. Update executable permissions
chmod +x "${TARGET_DIR}/agy_memory.py" 2>/dev/null || true
chmod +x "${TARGET_DIR}/agy_memory_mcp.py" 2>/dev/null || true
chmod +x "${TARGET_DIR}/dashboard.py" 2>/dev/null || true
chmod +x "${TARGET_DIR}/memory_worker.py" 2>/dev/null || true
chmod +x "${TARGET_DIR}/scripts/cron_runner.sh" 2>/dev/null || true
chmod +x "${TARGET_DIR}/scripts/auto_sync_hook.py" 2>/dev/null || true
chmod +x "${TARGET_DIR}/scripts/backfill_recent.py" 2>/dev/null || true
chmod +x "${TARGET_DIR}/scripts/install_macbook.sh" 2>/dev/null || true
chmod +x "${TARGET_DIR}/scripts/hooks/pre-commit" 2>/dev/null || true

# 2. Setup convenience symlinks in ~/bin
mkdir -p "${HOME}/bin"
ln -sf "${TARGET_DIR}/agy_memory.py" "${HOME}/bin/agy-memory"
echo "🔗 Symlink registered: ~/bin/agy-memory -> ${TARGET_DIR}/agy_memory.py"

# 3. Ensure Extern2TB storage hierarchy exists
echo "📁 Ensuring Extern2TB storage directories..."
mkdir -p "${STORAGE_ROOT}/data"
mkdir -p "${STORAGE_ROOT}/archive"
mkdir -p "${STORAGE_ROOT}/cache/fastembed"
mkdir -p "${STORAGE_ROOT}/logs"
mkdir -p "/Volumes/Extern2TB/GitHub/_Logs/agy-memory-engine"

# 4. Install git pre-commit hook if in git repo
if [ -d "${TARGET_DIR}/.git" ]; then
    mkdir -p "${TARGET_DIR}/.git/hooks"
    cp "${TARGET_DIR}/scripts/hooks/pre-commit" "${TARGET_DIR}/.git/hooks/pre-commit"
    chmod +x "${TARGET_DIR}/.git/hooks/pre-commit"
    echo "🪝 Git pre-commit hook installed in .git/hooks/pre-commit"
fi

echo "✅ Setup complete!"
