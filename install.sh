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

# ── Fetch project version ─────────────────────────────────────────────────────

RELEASE_VERSION=$(curl -fsSL "${BASE_URL}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

# ── Header ────────────────────────────────────────────────────────────────────

echo ""
hr
echo "  ha-smart-ev-charging — installer"
echo "  Release : ${RELEASE_VERSION}  (git ref: ${VERSION})"
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
    "${CONFIG_DIR}"/packages/evcharging/evcharging_*.yaml
    "${CONFIG_DIR}"/packages/evcharging/evcharging_*.yml
    "${CONFIG_DIR}"/lovelace/evcharging_*.yaml
    "${CONFIG_DIR}"/lovelace/evcharging_*.yml
)
shopt -u nullglob

if [ ${#LEGACY_FILES[@]} -gt 0 ]; then
    echo ""
    warn "Legacy 'evcharging_*' files from a previous install were found — these"
    warn "will CLASH with the new 'ev_*' files (duplicate entity definitions →"
    warn "YAML silently drops one block → entities disappear at runtime):"
    for f in "${LEGACY_FILES[@]}"; do
        echo "      $f"
    done
    echo ""
    warn "Either delete them, or rename them to something other than .yaml/.yml"
    warn "(e.g. *.disabled) to opt out of HA's package loader. Then re-run."
    echo ""
    echo "      # Disable (keeps the files around):"
    for f in "${LEGACY_FILES[@]}"; do
        echo "      mv \"$f\" \"$f.disabled\""
    done
    echo ""
    echo "      # Or delete:"
    for f in "${LEGACY_FILES[@]}"; do
        echo "      rm \"$f\""
    done
    echo ""
    echo "      # Also remove any stale dashboard registration in configuration.yaml"
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

# Record installed version (hidden file — not loaded by HA)
echo "$RELEASE_VERSION" > "${CONFIG_DIR}/packages/.ev_charging_version"
ok "packages/.ev_charging_version  (${RELEASE_VERSION})"

echo ""

# ── Peblar Modbus integration (optional) ──────────────────────────────────────
# The template is always downloaded as a reference.
# If ev_peblar_modbus.yaml already exists it is safe to overwrite — the
# charger host lives in secrets.yaml (peblar_host), not in this file.
# The file is NOT created automatically on first install: activating Modbus
# while the official REST integration is still running will break charging.

MODBUS_TEMPLATE="${CONFIG_DIR}/packages/ev_peblar_modbus.yaml.template"
MODBUS_TARGET="${CONFIG_DIR}/packages/ev_peblar_modbus.yaml"
MODBUS_NOT_INSTALLED=false
MODBUS_SECRET_MISSING=false

echo "Peblar Modbus integration:"

download "packages/ev_peblar_modbus.yaml.template" "$MODBUS_TEMPLATE"
ok "packages/ev_peblar_modbus.yaml.template  (reference template — updated)"

if [ ! -f "$MODBUS_TARGET" ]; then
    MODBUS_NOT_INSTALLED=true
    warn "packages/ev_peblar_modbus.yaml not found — Modbus not active. See next steps below."
else
    download "packages/ev_peblar_modbus.yaml.template" "$MODBUS_TARGET"
    ok "packages/ev_peblar_modbus.yaml  (updated)"
    if ! grep -q "peblar_host" "${CONFIG_DIR}/secrets.yaml" 2>/dev/null; then
        MODBUS_SECRET_MISSING=true
        warn "secrets.yaml does not contain 'peblar_host'. Add:"
        warn "    peblar_host: 192.168.1.x  # your Peblar charger's IP or hostname"
        warn "Then validate YAML and restart HA."
    fi
fi

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
    warn "Dashboard not registered in configuration.yaml."
    warn "Add the following to configuration.yaml, inside the 'lovelace: dashboards:' block:"
    echo ""
    echo "      lovelace:"
    echo "        dashboards:"
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
echo "  Done! (installed release ${RELEASE_VERSION})"
echo ""
echo "  Next steps:"
echo ""
STEP=1
if [ "$NEEDS_ACTION" = true ]; then
    echo "  ${STEP}. Update configuration.yaml (see warnings above)"
    STEP=$((STEP+1))
fi
echo "  ${STEP}. Make sure required integrations are installed and configured"
echo "     (your EV brand, Frank Energie / Entso-e, P1 meter, ...)"
STEP=$((STEP+1))
if [ "$MODBUS_NOT_INSTALLED" = true ]; then
    echo "  ${STEP}. Remove the official Peblar integration before enabling Modbus:"
    echo "     Settings → Devices & Services → Peblar → Delete"
    STEP=$((STEP+1))
fi
echo "  ${STEP}. Validate your YAML:"
echo "     Developer Tools → YAML → Check Configuration"
STEP=$((STEP+1))
echo "  ${STEP}. Restart Home Assistant:"
echo "     Settings → System → Restart → Restart Home Assistant"
STEP=$((STEP+1))
if [ "$MODBUS_NOT_INSTALLED" = true ]; then
    echo "  ${STEP}. After restart — delete leftover Peblar entities:"
    echo "     Developer Tools → States → search for 'peblar'"
    echo "     Delete any entities still listed as 'unavailable'."
    STEP=$((STEP+1))
    echo "  ${STEP}. Activate Peblar Modbus:"
    echo "     a) Add your charger's IP/hostname to secrets.yaml:"
    echo "        peblar_host: 192.168.1.x"
    echo "     b) Copy the template:"
    echo "        cp /config/packages/ev_peblar_modbus.yaml.template \\"
    echo "           /config/packages/ev_peblar_modbus.yaml"
    STEP=$((STEP+1))
    echo "  ${STEP}. Validate YAML and restart HA again (same as the two steps above)."
    STEP=$((STEP+1))
elif [ "$MODBUS_SECRET_MISSING" = true ]; then
    echo "  ${STEP}. Add your charger's IP/hostname to secrets.yaml (see warning above)."
    echo "     Then validate YAML and restart HA again (same as the two steps above)."
    STEP=$((STEP+1))
fi
echo "  ${STEP}. Run script.ev_apply_defaults:"
echo "     Developer Tools → Services → search 'ev_apply_defaults' → Call"
echo "     Sets sensible starting values for all EV helpers."
STEP=$((STEP+1))
echo "  ${STEP}. Open the EV Charging dashboard and configure to taste"
echo ""
hr
echo ""
