#!/usr/bin/env bash
# ha-smart-ev-charging — install / update script
#
# Usage (from your Home Assistant /config directory):
#   bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/ha-smart-ev-charging/main/install.sh)
#
# To install from the dev branch:
#   EV_VERSION=dev bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/ha-smart-ev-charging/dev/install.sh)
#
# To install a specific release tag:
#   EV_VERSION=v1.0.0 bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/ha-smart-ev-charging/main/install.sh)
#
# Tip: use the SSH add-on (community) to get a terminal on your HA instance.

set -euo pipefail

REPO="Dennis-Q/ha-smart-ev-charging"
VERSION="${EV_VERSION:-}"
CONFIG_DIR="$(pwd)"

# ── Colour / output helpers ───────────────────────────────────────────────────

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
info() { echo -e "  ${CYAN}ℹ${RESET}  $*"; }
say()  { echo "    $*"; }
hr()   { echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
ask()  { local _a; read -rp "  ? $* [y/N] " _a; [[ "${_a,,}" == "y" ]]; }

# ── Sanity checks ─────────────────────────────────────────────────────────────

if ! command -v curl &>/dev/null; then
    echo "ERROR: curl is required but not found. Install it and retry."
    exit 1
fi

if [ ! -f "${CONFIG_DIR}/configuration.yaml" ]; then
    echo "ERROR: configuration.yaml not found in $(pwd)."
    echo "Run this script from your Home Assistant config directory (/config)."
    exit 1
fi

# ── Version resolution ────────────────────────────────────────────────────────
#
# Resolution order:
#   1. EV_VERSION env var (release tag, branch name, or commit SHA)
#   2. Latest GitHub release tag
#   3. main branch

if [ -z "$VERSION" ]; then
    LATEST=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
             | grep '"tag_name"' | cut -d'"' -f4 2>/dev/null || true)
    if [ -n "$LATEST" ]; then
        VERSION="$LATEST"
    else
        VERSION="main"
        warn "No releases found — installing from main branch."
        echo ""
    fi
fi

BASE_URL="https://raw.githubusercontent.com/${REPO}/${VERSION}"

# ── Download helper ───────────────────────────────────────────────────────────

download() {
    local src="$1" dst="$2"
    curl -fsSL "${BASE_URL}/${src}" -o "${dst}"
}

# ── Header ────────────────────────────────────────────────────────────────────

echo ""
hr
echo "  ha-smart-ev-charging — installer"
echo "  Version : ${VERSION}"
echo "  Target  : ${CONFIG_DIR}"
hr
echo ""

# ── Project caveat ────────────────────────────────────────────────────────────

info "This project is private-use and not adapted for general distribution."
info "See README.md for required integrations (Peblar, EV brand, dynamic tariffs, ...)."
echo ""

# ── Legacy file check ─────────────────────────────────────────────────────────
# Pre-rename installs used the 'evcharging_' file prefix. If those files
# are still being LOADED by HA alongside the new 'ev_' prefix files, every
# helper / sensor is defined twice and YAML silently drops one block —
# entities then disappear at runtime with no error message.
#
# Glob matches only .yaml / .yml — renaming a legacy file to *.disabled
# (or any other extension) opts out of this check, which is the
# documented way to keep an old file around without removing it.

shopt -s nullglob
LEGACY_FILES=(
    "${CONFIG_DIR}"/packages/evcharging_*.yaml
    "${CONFIG_DIR}"/packages/evcharging_*.yml
    "${CONFIG_DIR}"/lovelace/evcharging_*.yaml
    "${CONFIG_DIR}"/lovelace/evcharging_*.yml
)
shopt -u nullglob

if [ ${#LEGACY_FILES[@]} -gt 0 ]; then
    echo ""
    warn "Legacy 'evcharging_*.{yaml,yml}' files from a previous install were"
    warn "found — these will CLASH with the new 'ev_*' files (duplicate entity"
    warn "definitions → YAML silently drops one block → entities disappear at"
    warn "runtime):"
    for f in "${LEGACY_FILES[@]}"; do
        echo "      $f"
    done
    echo ""
    warn "Either delete them, or rename them to something other than .yaml/.yml"
    warn "(e.g. *.disabled) to opt out of HA's package loader without losing"
    warn "the file. Then re-run this installer."
    echo ""
    echo "      # Delete:"
    echo "      rm ${CONFIG_DIR}/packages/evcharging_*.yaml ${CONFIG_DIR}/lovelace/evcharging_*.yaml"
    echo ""
    echo "      # Or disable (keeps the file around):"
    echo "      for f in ${CONFIG_DIR}/packages/evcharging_*.yaml ${CONFIG_DIR}/lovelace/evcharging_*.yaml; do"
    echo "        [ -e \"\$f\" ] && mv \"\$f\" \"\$f.disabled\""
    echo "      done"
    echo ""
    echo "      # And remove the stale dashboard registration in configuration.yaml"
    echo "      # (look for 'filename: lovelace/evcharging_dashboard.yaml')"
    echo ""
    echo "Aborting to avoid leaving you with a broken install."
    exit 1
fi

# ── Create directories ────────────────────────────────────────────────────────

mkdir -p "${CONFIG_DIR}/packages"
mkdir -p "${CONFIG_DIR}/lovelace"

# ── Core EV files — always overwrite ─────────────────────────────────────────
# Safe to overwrite on every update; no user-editable content in these files.
# All user state lives in input_* helpers, which are preserved across updates.

echo "Core files:"

CORE_FILES=(
    packages/ev_generic.yaml
    packages/ev_solar.yaml
    packages/ev_window.yaml
)

for f in "${CORE_FILES[@]}"; do
    download "$f" "${CONFIG_DIR}/${f}"
    ok "$f"
done

# Dashboard is at repo root but lands under lovelace/ in /config
download "dashboard.yaml" "${CONFIG_DIR}/lovelace/ev_dashboard.yaml"
ok "lovelace/ev_dashboard.yaml"

echo ""

# ── configuration.yaml checks ─────────────────────────────────────────────────

CONF="${CONFIG_DIR}/configuration.yaml"
NEEDS_ACTION=false

if ! grep -q "include_dir_named packages" "$CONF" 2>/dev/null; then
    warn "Packages directory not included in configuration.yaml. Add:"
    echo ""
    echo "      homeassistant:"
    echo "        packages: !include_dir_named packages"
    echo ""
    NEEDS_ACTION=true
fi

if ! grep -q "ev_dashboard.yaml" "$CONF" 2>/dev/null; then
    warn "Dashboard not registered in configuration.yaml. Add inside lovelace > dashboards:"
    echo ""
    echo "          ev-charging:"
    echo "            mode: yaml"
    echo "            title: EV Charging"
    echo "            icon: mdi:ev-station"
    echo "            show_in_sidebar: true"
    echo "            filename: lovelace/ev_dashboard.yaml"
    echo ""
    NEEDS_ACTION=true
fi

# ── Done ──────────────────────────────────────────────────────────────────────

hr
echo "  Done! Next steps:"
echo ""
if [ "$NEEDS_ACTION" = true ]; then
    echo "  1. Update configuration.yaml (see warnings above)"
    echo "  2. Make sure required integrations are installed and configured"
    echo "     (Peblar, your EV brand, Frank Energie / Entso-e, ...)"
    echo "  3. Restart Home Assistant"
    echo "  4. Run script.ev_apply_defaults from Developer Tools → Services"
    echo "     to set sensible starting values for all EV helpers"
    echo "  5. Open the EV Charging dashboard and configure to taste"
else
    echo "  1. Make sure required integrations are present (Peblar, EV brand, ...)"
    echo "  2. Reload YAML or restart Home Assistant"
    echo "  3. Run script.ev_apply_defaults once after a fresh install"
fi
echo ""
hr
echo ""
