# Peblar Modbus integration (`ev_peblar_modbus.yaml.template`)

`packages/ev_peblar_modbus.yaml.template` is the template for a drop-in
replacement of the official Peblar Home Assistant REST integration. Copy it to
your `/config/packages/` directory, rename it to `ev_peblar_modbus.yaml`, and
set your charger's IP address. It controls the charger over Modbus TCP instead
of the REST API, which unlocks **milliamp-precision current control** — the
main reason to use this instead of the official integration.

> **Status:** production-ready, validated on firmware `1.9.0+1+COOLBLUE-1`,
> Modbus API `1.0`.

---

## Why Modbus instead of the official integration?

The official REST integration exposes a charge-limit slider in whole amps
(6–16 A). At low solar excess the quantisation error is significant: rounding
to the nearest amp at 230 V wastes up to ~230 W of available solar per cycle.

The Modbus API exposes register `40000` as a 32-bit milliamp value
(6 000–16 000 mA in 1 mA steps), so the solar control loop can target the
exact available power without rounding to whole amps.

---

## Requirements

- Peblar EV charger with firmware ≥ 1.6.
- **Modbus TCP enabled and set to Read/Write** in the Peblar web interface:
  Settings → Connectivity → Modbus API → enable, access level = **Read/Write**.
  Read-only mode is not sufficient — the integration must be able to write the
  current setpoint and phase-mode registers.
- The charger must be reachable on your LAN. Default port: **502**.

> **REST API:** Consider setting the Peblar REST API to read-only
> (same settings page) so it cannot interfere if the official HA integration is
> ever re-added by accident. Note that the official Peblar HA integration
> re-enables the REST API when active, so removing it from HA
> (Settings → Devices & Services) is the more reliable safeguard.

> **Important:** The official REST integration must be removed **before**
> activating this file. The Peblar applies the lowest limit across all active
> control sources. If the REST integration is still present and sets its limit
> to 0 (e.g. when its charge switch is off), it will override the Modbus
> setpoint and block charging entirely.

---

## Installation

1. **Remove the official Peblar REST integration** from
   Settings → Devices & Services. After removal, check for leftover entities
   in Developer Tools → States — filter on `peblar` and delete any
   that are still listed with state `unavailable`.

2. **Add your charger's IP/hostname to `secrets.yaml`** (one-time, never needs
   changing again):

   ```yaml
   peblar_host: 192.168.1.x   # your Peblar charger's IP address or hostname
   ```

3. **Install the Modbus package.** Two options:

   **Option A — via `install.sh`** (recommended if you used it to install the
   project): re-run the installer and it will print the activation steps.

   ```sh
   bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/ha-smart-ev-charging/main/install.sh)
   ```

   **Option B — manually**: copy the template:

   ```sh
   cp /config/packages/ev_peblar_modbus.yaml.template \
      /config/packages/ev_peblar_modbus.yaml
   ```

   The `host:` in this file reads from `secrets.yaml` via `!secret peblar_host`
   — no further editing of the yaml file is needed.

5. Do a **full HA restart** (not just reload) — the Modbus hub only
   initialises at startup.

6. Verify entities appear in Developer Tools → States under the
   `peblar_ev_charger_*` namespace.

---

## Entities provided

All entity IDs match the official REST integration exactly, so existing
automations and dashboard cards work without changes.

### Switches

| Entity | Purpose |
|---|---|
| `switch.peblar_ev_charger_charge` | On = charging allowed; off writes 0 mA to the setpoint register |
| `switch.peblar_ev_charger_force_single_phase` | On = force L1-only charging; off = 3-phase allowed |

### Numbers (charge limit)

| Entity | Range | Purpose |
|---|---|---|
| `number.peblar_ev_charger_charge_limit` | 6–16 A | Integer-amp slider — matches the official integration. Reads the effective limit from the charger. |
| `number.peblar_ev_charger_charge_current_limit_ma` | 6 000–16 000 mA | **Milliamp setpoint** — the main advantage over REST. Use this in solar automations for precise control. |

### Sensors — charger state

| Entity | Notes |
|---|---|
| `sensor.peblar_ev_charger_state` | `no_ev_connected` / `suspended` / `charging` / `error` / `fault` / `invalid` / `unknown` |
| `sensor.peblar_ev_charger_limit_source` | Active limit source, e.g. `local_modbus_api`, `installation_limit`, `charging_cable` |
| `sensor.peblar_ev_charger_lock_state` | `locked` / `unlocked` / `unknown` |
| `sensor.peblar_ev_charger_uptime` | Charger boot time as `device_class: timestamp` |

### Sensors — power & energy

| Entity | Scan | Notes |
|---|---|---|
| `sensor.peblar_ev_charger_power` | 1 s | Total W — main signal for solar control |
| `sensor.peblar_ev_charger_power_phase_1/2/3` | 5 s | Per-phase W |
| `sensor.peblar_ev_charger_voltage_phase_1/2/3` | 10 s | Per-phase V — used by solar amps calculation |
| `sensor.peblar_ev_charger_current_phase_1/2/3` | 5 s | Per-phase A |
| `sensor.peblar_ev_charger_current_total` | template | Sum of phase currents (A) |
| `sensor.peblar_ev_charger_session_energy` | 60 s | kWh this session |
| `sensor.peblar_ev_charger_lifetime_energy` | 60 s | kWh lifetime total |

### Binary sensors — warnings & errors

| Entity | Attribute | Notes |
|---|---|---|
| `binary_sensor.peblar_ev_charger_active_warnings` | `active_warning_codes` (list) | ON when any warning slot > 0 |
| `binary_sensor.peblar_ev_charger_active_errors` | `active_error_codes` (list) | ON when any error slot > 0 |

The `active_warning_codes` / `active_error_codes` attributes contain the raw
numeric codes (e.g. `[10400]`). Look them up in the Peblar charger web
interface or documentation.

### Numbers — Modbus watchdog

| Entity | Notes |
|---|---|
| `number.peblar_ev_charger_alive_timeout` | Seconds before Modbus watchdog trips (0 = disabled) |
| `number.peblar_ev_charger_fallback_current` | Current the charger falls back to on watchdog timeout |

### System information (diagnostic)

`sensor.peblar_ev_charger_firmware_version`, `…product_sn`, `…product_pn`,
`…hardware_identifier`, `…modbus_api_version_major/minor`,
`…phase_count`, `…independent_relays`, `…wlan_signal_strength`,
`…cellular_signal_strength` — scanned hourly or every 60 s; mainly
useful for diagnostics and version checks.

---

## What's not available via Modbus

These features exist in the official REST integration but have no Modbus
register equivalent:

| Feature | Impact |
|---|---|
| `select.peblar_ev_charger_smart_charging` (default / fast_solar / pure_solar / scheduled / smart_solar) | Not needed — `ev_solar.yaml` implements its own solar logic using the mA setpoint directly |
| `button.peblar_ev_charger_identify` | Can't flash the LED from HA; use the charger web UI |
| `button.peblar_ev_charger_reboot` | Can't remotely restart the charger from HA; use the charger web UI |
| Firmware update notifications (`update.*`) | Not available; check the Peblar web UI or app for updates |

---

## Rate-limit warning

The Peblar firmware raises **warning code 10400** and pauses charging for
~15 minutes if `switch.peblar_ev_charger_charge` or
`switch.peblar_ev_charger_force_single_phase` is toggled more than
**3 times in 10 minutes**.

**Use the mA setpoint (`number.peblar_ev_charger_charge_current_limit_ma`)
for fine-grained power control** — writes to register 40000 are not
rate-limited. Only toggle the switches for actual start/stop or phase-mode
transitions.

---

## Internal backing entities (not for direct use)

The following sensors read raw Modbus register values and back the
user-facing template entities above. They are excluded from the recorder.
Do not use them directly in automations — use the template entities instead.

`sensor.peblar_ev_charger_charge_current_limit_raw`,
`…force_single_phase_raw`, `…charge_current_limit_actual`,
`…cp_state_raw`, `…lock_state_raw`, `…limit_source_raw`,
`…alive_timeout_raw`, `…fallback_current_raw`, `…uptime_raw`
