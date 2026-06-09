# Changelog

All notable changes to this project will be documented here.

## [0.2.1] – 2026-06-09

### Fixed
- **Peblar charge current entity** — two automations in `ev_generic.yaml` referenced the
  deprecated `number.peblar_ev_charger_charge_limit` (6–16 A) with value `16`. Corrected
  to `number.peblar_ev_charger_charge_current_limit_ma` with value `16000` mA, consistent
  with how `ev_solar.yaml` already writes the charge current. (Thanks Mik3yZ — PR #2)

## [0.2.0] – 2026-06-09

### Added
- **`binary_sensor.ev_solar_viable`** — gates solar mode on actual measured panel production rather than sunrise/sunset. Requires configurable solar power entities to exceed `ev_solar_min_charge_threshold_w` for 2 minutes (delay_on) before activating solar mode; 5-minute delay_off prevents flickering. Falls back to sun elevation > 5° when no solar entities are configured.
- **`battery_assist` charging mode** — new mode above `solar` in the dispatch order. Active when `input_boolean.ev_battery_assist_charging` is on and the configured `ev_home_battery_assist_active_entity` is `on`. Reuses the solar surplus-tracking control loop; the grid balance equation naturally regulates EV current to available battery discharge capacity minus house load (no separate control path needed).
- **Configurable power entity references** — four new `input_text` helpers to point at install-specific entities without editing package files:
  - `ev_solar_power_entity_1` / `ev_solar_power_entity_2` — solar inverter power sensors (W)
  - `ev_home_battery_power_entity` — home battery power sensor (W, positive = charging)
  - `ev_home_battery_assist_active_entity` — `on`/`off` entity that signals the home battery is actively assisting EV charging
- **Home battery zero-balance correction in `ev_grid_excess_power`** — when a home battery is configured and absorbing solar (keeping grid ≈ 0), the excess calculation now adds back the battery's positive (charging) component so solar surplus is visible to the EV control loop.
- **`binary_sensor.ev_power_entity_unit_mismatch`** — detects when any configured solar or home battery power entity reports in kW instead of W; attributes list per-entity units for diagnosis.
- **Unit mismatch notification** — push + persistent notification when `ev_power_entity_unit_mismatch` turns on; auto-dismissed when resolved.
- **Dashboard: Power entities section** in Advanced Settings with all four `input_text` fields, status binary sensors, and inline documentation.
- **Dashboard: `ev_battery_assist_charging` toggle** in EV Charging Settings.
- **Dashboard: warning banners** for power entity unit mismatch (red) and P1 unit mismatch (red, was yellow).

### Fixed
- **Charger stays on after window/cheapest → solar transition with no surplus** — added `ev_mode_entry` trigger (fires 2 min after mode enters `solar` or `battery_assist`). If `ev_optimal_charging_phase_mode` is already `stop` and the charger is still on, it turns the charger off. `mode: restart` on the automation ensures live phase-mode triggers cancel this if solar ramps up quickly.
- **Solar mode activates at astronomical sunrise** instead of when panels actually produce — replaced `sun.sun above_horizon` with `binary_sensor.ev_solar_viable` (see above).
- **Template conditions in automations** replaced with native `or:`/`and:` condition blocks (`ev_solar_charge_mode_control` and `ev_solar_dynamic_power_control`).
- **Pre-existing bug in `sensor.ev_expected_charging_limit`** — `tarif_optimization` variable was referenced but never assigned in the dispatch template.

---

## [0.1.6] – 2026-06-05

### Added
- Notification dispatch script (`script.ev_send_notification`) and test button on dashboard.

### Fixed
- `install.sh`: migration check for old package location (`packages/ev_*.yaml`) was always triggering even on fresh installs.
- `install.sh`: migration step failed when `packages/ev/` directory did not yet exist.

---

## [0.1.5] – 2026-06-03

### Changed
- Excess power smoothing switched from mean-of-3 to **median-of-5** — rejects single-sample P1 glitches and brief appliance spikes without slowing cloud-shadow response.
- Packages moved from `packages/` to `packages/ev/` subdirectory; `install.sh` and `MODBUS-README.md` updated accordingly.
- `ev_peblar_modbus.yaml.template` renamed to `ev_peblar_modbus.yaml`.
- Smoothing sensor renamed from `ev_grid_excess_power_last_3_average` → `ev_grid_excess_power_smoothed`.

---

## [0.1.4] – 2026-06-02

### Added
- **Step E: milliamp solar control** — writes to `charge_current_limit_ma` (6 000–16 000 mA) for 1 mA precision instead of whole-amp steps.
- New mA-granularity sensors excluded from recorder to keep DB size down.

---

## [0.1.3] – 2026-06-01

### Changed
- `install.sh`: interactive Modbus activation flow — prompts the user to confirm the official Peblar REST integration has been removed before creating `ev_peblar_modbus.yaml`. Template copy in packages removed.

---

## [0.1.2] – 2026-06-01

### Changed
- Peblar Modbus hub `host:` moved to `!secret peblar_host` — no longer hardcoded in the package file.

### Fixed
- `install.sh`: legacy file cleanup used an uninitialized array variable; replaced with inline globs.

---

## [0.1.1] – 2026-06-01

### Fixed
- `ev_peblar_modbus.yaml`: all 55 `unique_id:` values corrected to match the `peblar_ev_charger_*` pattern required for correct entity ID generation.
- `ev_solar.yaml`: removed stale kW auto-scaling from excess calculation (only the detection/warning remains).
- `install.sh`: step ordering and `configuration.yaml` dashboard snippet clarified.

### Added
- `binary_sensor.ev_p1_unit_mismatch` — turns on when P1 consumption or production sensor reports a unit other than W.
- Dashboard: P1 unit mismatch warning banner.

---

## [0.1.0] – 2026-05-29

Initial release.

- EV charging modes: `force`, `solar`, `cheapest` (ENTSO-e window), `window`, `none`.
- Peblar EV charger controlled via Modbus TCP (`ev_peblar_modbus.yaml`).
- Solar surplus calculation from P1 meter (`ev_solar.yaml`).
- Dynamic tariff window charging (`ev_window.yaml`).
- Lovelace dashboard (`dashboard.yaml`).
- `install.sh` installer with legacy file migration and interactive Modbus setup.
- `MODBUS-README.md` — full installation guide and entity reference.
