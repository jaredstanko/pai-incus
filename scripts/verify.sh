#!/bin/bash
# PAI Linux — End-State Verification
# Checks that the full system matches the expected state from versions.env.
# Uses 3-state model: PINNED (exact match), DRIFTED (acceptable), FAILED (blocking).
#
# Can be run standalone or called by install.sh at the end of install.
#
# Usage:
#   ./scripts/verify.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Colors ---------------------------------------------------------------

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
DRIFT=0
FAIL=0

# --- Load version manifest ------------------------------------------------

VERSIONS_FILE="$SCRIPT_DIR/../versions.env"
if [ ! -f "$VERSIONS_FILE" ]; then
  # Try parent directory
  VERSIONS_FILE="$SCRIPT_DIR/versions.env"
fi
if [ ! -f "$VERSIONS_FILE" ]; then
  echo -e "${RED}✗${NC} versions.env not found"
  exit 1
fi
source "$VERSIONS_FILE"

# --- Helpers --------------------------------------------------------------

pinned() {
  local label="$1"
  local detail="${2:-}"
  if [ -n "$detail" ]; then
    printf "  ${GREEN}%-8s${NC} %-40s %s\n" "PINNED" "$label" "$detail"
  else
    printf "  ${GREEN}%-8s${NC} %s\n" "PINNED" "$label"
  fi
  PASS=$((PASS + 1))
}

drifted() {
  local label="$1"
  local detail="${2:-}"
  if [ -n "$detail" ]; then
    printf "  ${YELLOW}%-8s${NC} %-40s %s\n" "DRIFTED" "$label" "$detail"
  else
    printf "  ${YELLOW}%-8s${NC} %s\n" "DRIFTED" "$label"
  fi
  DRIFT=$((DRIFT + 1))
}

failed() {
  local label="$1"
  local detail="${2:-}"
  if [ -n "$detail" ]; then
    printf "  ${RED}%-8s${NC} %-40s %s\n" "FAILED" "$label" "$detail"
  else
    printf "  ${RED}%-8s${NC} %s\n" "FAILED" "$label"
  fi
  FAIL=$((FAIL + 1))
}

check_version() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  if [ -z "$actual" ] || [ "$actual" = "MISSING" ]; then
    failed "$label" "(not installed)"
  elif [ "$actual" = "$expected" ]; then
    pinned "$label" "($actual)"
  else
    drifted "$label" "(expected: $expected, got: $actual)"
  fi
}

check_exists() {
  local label="$1"
  local path="$2"

  if [ -e "$path" ]; then
    pinned "$label"
  else
    failed "$label" "(not found: $path)"
  fi
}

check_command() {
  local label="$1"
  local cmd="$2"

  if command -v "$cmd" &>/dev/null; then
    pinned "$label"
  else
    failed "$label" "($cmd not in PATH)"
  fi
}

# --- Banner ---------------------------------------------------------------

echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  PAI Linux — System Verification${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════${NC}"
echo ""
echo "  Checking against versions.env manifest..."
echo ""

# =========================================================================
# HOST CHECKS (run on Linux host)
# =========================================================================

echo -e "${BOLD}  Host (Linux)${NC}"
echo -e "  ──────────────────────────────────────────────"

# Linux
if [[ "$(uname -s)" = "Linux" ]]; then
  pinned "Linux" "($(uname -r))"
else
  failed "Linux" "(not Linux)"
fi

# Architecture
ARCH="$(uname -m)"
if [[ "$ARCH" = "x86_64" || "$ARCH" = "aarch64" ]]; then
  pinned "Architecture" "($ARCH)"
else
  failed "Architecture" "($ARCH)"
fi

# systemd
check_command "systemd" "systemctl"

# Incus
if command -v incus &>/dev/null; then
  INCUS_VER=$(incus version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  pinned "Incus" "($INCUS_VER)"
else
  failed "Incus" "(incus not found)"
fi

# CLI commands
for cmd in pai-start pai-stop pai-status pai-talk pai-shell; do
  check_command "$cmd" "$cmd"
done

# Workspace directories
WORKSPACE="$HOME/pai-workspace"
WORKSPACE_OK=true
for dir in claude-home data exchange portal work upstream; do
  if [ ! -d "$WORKSPACE/$dir" ]; then
    WORKSPACE_OK=false
    failed "Workspace: $dir" "(not found: $WORKSPACE/$dir)"
  fi
done
if [ "$WORKSPACE_OK" = true ]; then
  pinned "Workspace directories (6/6)"
fi

# =========================================================================
# CONTAINER CHECKS (run inside Incus container)
# =========================================================================

echo ""
echo -e "${BOLD}  Container (Incus)${NC}"
echo -e "  ──────────────────────────────────────────────"

CONTAINER="pai"

# Check container exists
if ! incus info "$CONTAINER" &>/dev/null 2>&1; then
  failed "Incus container '$CONTAINER'" "(does not exist)"
  echo ""
  echo -e "  ${RED}Cannot check container internals — container does not exist.${NC}"
else
  CONTAINER_STATUS=$(incus info "$CONTAINER" 2>/dev/null | grep "^Status:" | awk '{print $2}')
  if [ "$CONTAINER_STATUS" = "RUNNING" ]; then
    pinned "Container '$CONTAINER'" "(running)"
  else
    drifted "Container '$CONTAINER'" "(status: $CONTAINER_STATUS, expected: RUNNING)"
  fi

  # Security checks
  PRIVILEGED=$(incus config get "$CONTAINER" security.privileged 2>/dev/null || echo "unknown")
  if [ "$PRIVILEGED" = "false" ] || [ "$PRIVILEGED" = "" ]; then
    pinned "Unprivileged container"
  else
    failed "Unprivileged container" "(security.privileged=$PRIVILEGED)"
  fi

  if [ "$CONTAINER_STATUS" = "RUNNING" ]; then
    # Batch all container checks into a single exec for speed
    VM_CHECK_SCRIPT='
      echo "BUN_VER=$(bun --version 2>/dev/null || echo MISSING)"
      echo "CLAUDE_VER=$(claude --version 2>/dev/null | grep -oE "[0-9.]+" | head -1 || echo MISSING)"
      echo "NODE_VER=$(node --version 2>/dev/null || echo MISSING)"
      echo "PAI_DIR=$(test -d /home/claude/.claude/PAI && echo YES || echo NO)"
      echo "PAI_LINK=$(test -L /home/claude/.claude/skills/PAI && echo YES || echo NO)"
      echo "BASHRC_ENV=$(grep -cF "# --- PAI environment" /home/claude/.bashrc 2>/dev/null || echo 0)"
      echo "ZSHRC_ENV=$(grep -cF "# --- PAI environment" /home/claude/.zshrc 2>/dev/null || echo 0)"
      echo "COMPANION=$(test -d /home/claude/pai-companion/companion && echo YES || echo NO)"
      echo "PW_VER=$(bunx playwright --version 2>/dev/null || echo MISSING)"
      echo "AUDIO_PW=$(test -S /tmp/pipewire-0 && echo YES || echo NO)"
      echo "AUDIO_PA=$(test -S /run/user/1000/pulse/native && echo YES || echo NO)"
      for m in .claude data exchange portal work upstream; do
        test -d "/home/claude/$m" && echo "MOUNT_${m}=YES" || echo "MOUNT_${m}=NO"
      done
    '
    VM_RESULTS=$(incus exec "$CONTAINER" --user 1000 --group 1000 -- bash -lc "$VM_CHECK_SCRIPT" 2>/dev/null || echo "")

    # Parse results
    get_val() { echo "$VM_RESULTS" | grep "^$1=" | cut -d= -f2- | tr -d '[:space:]'; }

    ACTUAL_BUN=$(get_val BUN_VER)
    check_version "Bun" "$BUN_VERSION" "$ACTUAL_BUN"

    ACTUAL_CLAUDE=$(get_val CLAUDE_VER)
    check_version "Claude Code" "$CLAUDE_CODE_VERSION" "$ACTUAL_CLAUDE"

    ACTUAL_NODE=$(get_val NODE_VER)
    if [ -n "$ACTUAL_NODE" ] && [ "$ACTUAL_NODE" != "MISSING" ]; then
      pinned "Node.js" "($ACTUAL_NODE)"
    else
      failed "Node.js"
    fi

    [ "$(get_val PAI_DIR)" = "YES" ] && pinned "PAI directory" || failed "PAI directory"
    [ "$(get_val PAI_LINK)" = "YES" ] && pinned "PAI skill symlink" || failed "PAI skill symlink"

    # Mount accessibility
    MOUNTS_OK=true
    for mount in .claude data exchange portal work upstream; do
      MOUNT_KEY="MOUNT_${mount}"
      if [ "$(get_val "$MOUNT_KEY")" != "YES" ]; then
        MOUNTS_OK=false
        failed "Container mount: $mount"
      fi
    done
    if [ "$MOUNTS_OK" = true ]; then
      pinned "Container mounts accessible (6/6)"
    fi

    [ "$(get_val BASHRC_ENV)" != "0" ] && pinned ".bashrc PAI environment block" || failed ".bashrc PAI environment block"
    [ "$(get_val ZSHRC_ENV)" != "0" ] && pinned ".zshrc PAI environment block" || failed ".zshrc PAI environment block"
    [ "$(get_val COMPANION)" = "YES" ] && pinned "PAI Companion repo" || failed "PAI Companion repo"

    ACTUAL_PW=$(get_val PW_VER)
    if [ -n "$ACTUAL_PW" ] && [ "$ACTUAL_PW" != "MISSING" ]; then
      check_version "Playwright" "$PLAYWRIGHT_VERSION" "$ACTUAL_PW"
    else
      drifted "Playwright" "(could not verify version)"
    fi

    # Audio
    AUDIO_PW=$(get_val AUDIO_PW)
    AUDIO_PA=$(get_val AUDIO_PA)
    if [ "$AUDIO_PW" = "YES" ]; then
      pinned "Audio passthrough" "(PipeWire)"
    elif [ "$AUDIO_PA" = "YES" ]; then
      pinned "Audio passthrough" "(PulseAudio)"
    else
      drifted "Audio passthrough" "(no socket — check host audio)"
    fi
  fi
fi

# =========================================================================
# Summary
# =========================================================================

echo ""
echo -e "  ──────────────────────────────────────────────"
TOTAL=$((PASS + DRIFT + FAIL))
echo -e "  ${GREEN}${PASS} PINNED${NC}  ${YELLOW}${DRIFT} DRIFTED${NC}  ${RED}${FAIL} FAILED${NC}  (${TOTAL} checks)"
echo ""

if [ $FAIL -gt 0 ]; then
  echo -e "  ${RED}Some checks failed.${NC} Review output above for details."
  echo -e "  Re-run ${BOLD}./install.sh${NC} to fix, or check ${BOLD}~/.pai-install.log${NC}"
  exit 1
elif [ $DRIFT -gt 0 ]; then
  echo -e "  ${YELLOW}Some versions drifted${NC} (likely Claude Code auto-update). Non-blocking."
  exit 0
else
  echo -e "  ${GREEN}All checks passed. System is deterministic.${NC}"
  exit 0
fi
