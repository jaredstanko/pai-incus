#!/bin/bash
# PAI Linux — Cleanup
# Removes everything installed by install.sh.
# Asks before removing workspace data.
#
# Usage:
#   ./scripts/uninstall.sh                 # Uninstall default instance
#   ./scripts/uninstall.sh --name=v2       # Uninstall named instance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source shared instance configuration
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh" "$@"

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
skip() { echo -e "  ${YELLOW}⊘${NC} $1 (not found)"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

echo ""
echo -e "${BOLD}${RED}═══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  PAI Linux — Cleanup${NC}"
if [ -n "$INSTANCE_SUFFIX" ]; then
  echo -e "${BOLD}  Instance: ${RED}${INSTANCE_NAME}${NC}"
fi
echo -e "${BOLD}${RED}═══════════════════════════════════════════════${NC}"
echo ""
echo "  This will remove PAI Linux components."
echo "  It will NOT uninstall Incus itself."
echo ""
echo "  Target: Container '${CONTAINER_NAME}', workspace '${WORKSPACE}/'"
echo ""

# ─── 1. Stop and remove Incus container ──────────────────────

echo -e "${CYAN}[1/4]${NC} ${BOLD}Incus container${NC}"

if command -v incus &>/dev/null; then
  STATUS=$(pai_container_status)
  if [ -n "$STATUS" ]; then
    if [ "$STATUS" = "RUNNING" ]; then
      echo "  Stopping container..."
      incus stop "$CONTAINER_NAME" --timeout 30 2>/dev/null || true
    fi
    echo "  Deleting container '${CONTAINER_NAME}'..."
    incus delete "$CONTAINER_NAME" --force 2>/dev/null || true
    ok "Container '${CONTAINER_NAME}' deleted"
  else
    skip "Container '${CONTAINER_NAME}'"
  fi
else
  skip "Incus not installed"
fi

# ─── 2. Remove Incus profile ────────────────────────────────

echo -e "${CYAN}[2/4]${NC} ${BOLD}Incus profile${NC}"

PROFILE_NAME="${INSTANCE_NAME}"
if incus profile show "$PROFILE_NAME" &>/dev/null 2>&1; then
  incus profile delete "$PROFILE_NAME" 2>/dev/null || true
  ok "Profile '${PROFILE_NAME}' deleted"
else
  skip "Profile '${PROFILE_NAME}'"
fi

# ─── 3. Remove CLI commands ────────────────────────────────

echo -e "${CYAN}[3/4]${NC} ${BOLD}CLI commands${NC}"

BIN_DIR="$HOME/.local/bin"
REMOVED_CMD=false

for cmd in pai-start pai-stop pai-status pai-talk pai-shell; do
  if [ -f "$BIN_DIR/$cmd" ]; then
    rm -f "$BIN_DIR/$cmd"
    ok "Removed $cmd"
    REMOVED_CMD=true
  fi
done

# Remove common.sh lib
LIB_DIR="$HOME/.local/lib/pai"
if [ -d "$LIB_DIR" ]; then
  rm -rf "$LIB_DIR"
  ok "Removed $LIB_DIR/"
fi

if [ "$REMOVED_CMD" = false ]; then
  skip "CLI commands"
fi

# Clean PATH addition from shell rc
for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rcfile" ] && grep -qF "# --- PAI Linux PATH ---" "$rcfile" 2>/dev/null; then
    sed -i '/# --- PAI Linux PATH ---/,/# --- end PAI Linux PATH ---/d' "$rcfile"
    ok "Removed PATH block from $(basename "$rcfile")"
  fi
done

# ─── 4. Workspace data (ASKS FIRST) ──────────────────────────

echo -e "${CYAN}[4/4]${NC} ${BOLD}Workspace data${NC}"

if [ -d "$WORKSPACE" ]; then
  echo ""
  echo -e "  ${RED}${BOLD}WARNING: ${WORKSPACE}/ contains your data!${NC}"
  echo ""
  echo "  This includes:"
  echo "    - claude-home/ — PAI config, settings, memory"
  echo "    - work/        — Projects and work-in-progress"
  echo "    - data/        — Persistent data"
  echo "    - exchange/    — File exchange"
  echo "    - portal/      — Web portal content"
  echo "    - upstream/    — Reference repos"
  echo ""

  # Show sizes
  echo "  Directory sizes:"
  du -sh "$WORKSPACE/"* 2>/dev/null | while read -r size dir; do
    echo "    $size  $(basename "$dir")"
  done
  echo ""

  echo -ne "  ${RED}Delete ${WORKSPACE}/ and ALL its contents? [y/N]:${NC} "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    rm -rf "$WORKSPACE"
    ok "Removed ${WORKSPACE}/"
  else
    warn "Kept ${WORKSPACE}/ — you can remove it manually later"
  fi
else
  skip "${WORKSPACE}/"
fi

# ─── Done ─────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  Cleanup complete${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo "  What was removed:"
echo "    - Incus container '${CONTAINER_NAME}'"
echo "    - Incus profile '${INSTANCE_NAME}'"
echo "    - CLI commands (pai-start, pai-stop, pai-status, pai-talk, pai-shell)"
echo ""
echo "  What was NOT removed:"
echo "    - Incus itself"
echo "    - This repo (pai-linux/)"
if [ -d "$WORKSPACE" ]; then
  echo "    - ${WORKSPACE}/ (you chose to keep it)"
fi
echo ""
echo "  To do a fresh install: ./install.sh${INSTANCE_SUFFIX:+ --name=${_PAI_NAME}}"
echo ""
