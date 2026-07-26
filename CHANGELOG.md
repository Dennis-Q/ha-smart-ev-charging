# Changelog

All notable changes to this project will be documented here.

## [0.2.12] – 2026-07-24

### Added
- **One-time force charge now ends on disconnect** — `input_boolean.ev_force_charge_once`
  auto-disables when the cable is unplugged, making it truly one-time rather than
  "until the 8-hour timeout." New automation `ev_force_charge_once_disable_on_disconnect`
  triggers on `binary_sensor.ev_is_connected` going `off` for 1 minute (the debounce
  absorbs transient unavailable/unknown reads, which also flip that sensor off), turns
  the boolean off, and notifies. The 8-hour timeout and reach-limit auto-disables remain
  as backstops. Permanent force charge is unaffected.

## [0.2.13] – 2026-07-24

### Fixed
- **Charger could resume on the next plug-in after a mode ended while disconnected.**
  The charge switch (Modbus reg 40000) is a persistent latch, and
  `ev_generic_charging_mode_control` stops it on `ev_charging_mode → none` — but that
  automation was gated entirely on `binary_sensor.ev_is_connected` being `on`, so when a
  mode turned to `none` while the cable was out (one-time force cleared on unplug,
  permanent force toggled off, or any mode disabled while disconnected), the stop was
  skipped and the switch stayed armed at its last mA. Re-plugging then resumed charging
  with no active mode. The "car connected" gate now lives on the *start* branch only
  (`mode_full_power`) — starting still requires a connected car — while the stop branch
  (`mode_none`) runs regardless of plug state, so the switch is never left armed across a
  disconnect. Fix is mode-agnostic: it covers one-time force, permanent force, and any
  other mode ending while unplugged. `solar` is unaffected (not a trigger of this
  automation; `ev_solar.yaml` drives it and delegates its final stop to this `none`
  branch).

## [0.2.14] – 2026-07-26

### Fixed
- **Tariff modes never started when the mode armed before the car was plugged in**
  (production incident 2026-07-26). `ev_generic_charging_mode_control` could only act on
  a *change* of `sensor.ev_charging_mode`, so a `force`/`cheapest`/`window` mode that
  became active while the cable was out was never applied when the car arrived: the
  mode-change trigger had already fired and no-oped on the connection gate, and plugging
  in produced no further trigger. On 2026-07-26 the mode went to `cheapest` at 14:56 with
  the car away, the car was plugged in at 15:04, and the charger sat idle through the
  cheapest hour of the day (€0.0558/kWh) until it was started by hand at 17:15 — 2 h 11 m
  lost. New `connected` trigger on `binary_sensor.ev_is_connected → on` (30 s settle)
  re-evaluates on plug-in; the start branch now also asserts `ev_charging_mode` is one of
  `force`/`cheapest`/`window`, so a plug-in during `solar`, `battery_assist` or `none`
  still starts nothing. `solar` never had this bug because it re-evaluates continuously
  via `ev_optimal_charging_phase_mode`; the tariff modes have no such heartbeat.

- **Solar loop regulated the charger with no car attached.** Nothing in the solar chain
  checked the plug: `ev_charging_mode` goes to `solar` on `ev_solar_viable` alone (sun/PV,
  not the car), and `ev_optimal_charging_phase_mode` is pure arithmetic on excess vs the
  thresholds. Both `ev_solar_charge_mode_control` and `ev_solar_dynamic_power_control`
  now require `binary_sensor.ev_is_connected` to be `on`. Previously the loop tracked
  surplus all day with an empty cable — on 2026-07-26, ~19 charge-switch toggles and mA
  writes every 3 s between 08:45 (unplug) and 15:04 (plug-in). Beyond the pointless
  Modbus traffic, this made "is the switch armed at plug-in time" a coin flip decided by
  cloud cover, which is what masked the trigger bug above: on 2026-07-24 the loop happened
  to leave the switch armed at 16:49 and the car charged on plug-in with no automation
  involvement, while on 2026-07-26 its last act before handing over to `cheapest` was a
  stop at 14:54:24 (the home batteries tapering off shrank the `batt_charge` term below
  `ev_solar_min_charge_threshold_w`). Stop actions are gated too: with no car there is
  nothing to stop, and the `mode_none` branch of `ev_generic_charging_mode_control`
  remains the unconditional disarm path across a disconnect (0.2.13).

- **`ev_grid_excess_power` invented 500 W when the charger power sensor was
  unavailable.** `charger_power` is *added* to excess (it is what the charger is
  currently drawing, which becomes available again if the loop backs off), so an
  over-stated fallback inflates excess and the loop commands more current than the
  surplus supports — pulling from the grid, silently, for as long as the sensor is
  unavailable. Now defaults to 0, which under-states excess instead and makes the loop
  back off or stop: the safe direction, and self-correcting once the sensor returns. The
  old 500 W was arbitrary and wrong in both directions — a phantom 500 W of surplus with
  no car attached, and ~4 kW short mid-session. Every other read of this sensor in the
  package already defaulted to 0.

## [0.2.11] – 2026-07-17

### Fixed
- **Modbus variant: charger could re-enable itself right after a stop** (production
  incident 2026-07-16). Register 40000 is both the on/off control and the mA setpoint,
  and the charge switch state mirrors a register polled at 1 s. A stop's 0-write could
  be followed within 1–2 s by a 6000 mA write from `ev_solar_dynamic_power_control`
  whose guard had passed on the stale `on` state — re-enabling charging *permanently*,
  because the rewrite keeps the poll reading ≥ 6000 so the stale guard never corrects
  itself (observed: automated stop at mode entry and a manual toggle both lost this
  race; only a lucky-timed second manual toggle broke the livelock).
  `switch.peblar_ev_charger_charge` `turn_off` now delegates to the internal
  `script.peblar_ev_charger_stop`: the 0 is written immediately (instant stop), mA
  writes are suppressed for the whole script run (script run state is synchronous —
  no poll lag), and the stop is only declared done once the switch reads `off`
  sustained for 4 s (filters phantom `off` from a failed poll), retrying up to 3×
  and notifying (ungated, high priority) if the charger never confirms. On failure the
  script exits so regulation degrades to minimum current instead of wedging.
  `turn_on` cancels a pending stop (later command wins). Re-writing 0 does not touch
  the 3-toggles/10-min budget — register writes are not rate-limited. Confirmation
  (and the end of write suppression) takes ~10 s after the toggle (see
  MODBUS-README.md, "Confirmed stop").

## [0.2.10] – 2026-07-12

### Fixed
- **`ev_charger_saturated` false positive during ordinary regulation** — the derated term
  compared the mA-fine commanded limit against `charge_current_limit_actual` with only a
  200 mA margin, but the actual sensor is quantized to whole amps: commanded 6350 mA with
  actual 6 A read as a permanent phantom derate, keeping the sensor `on` while the charger
  was regulating normally (observed live at 1460 W / ~6.3 A). The commanded value is now
  floored to whole amps before the comparison; a genuine load-balancing derate is ≥ 1 A,
  so no real derating is missed.

## [0.2.9] – 2026-07-12

### Added
- **`binary_sensor.ev_charger_saturated`** — ON when the charger cannot take more power
  than it currently delivers: commanded current limit pinned at the 16 A maximum (covers
  1-phase max, 3-phase max, and the phase-switch hysteresis band), OR
  `charge_current_limit_actual` (= min(commanded, externally available)) dropping below the
  commanded value, meaning CT/household load balancing is the binding constraint.
  `delay_on` 1:30 / `delay_off` 3:00 provide hysteresis so downstream consumers see
  transitions minutes apart at worst. Built for home battery coordination: point HBA's
  `input_text.hba_strategy_ev_saturated_entity_id` at this sensor so "Charge PV during EV
  charge" only runs while the charger is a constant load (genuinely unconsumable surplus)
  and never competes with the charger's own regulation. Known blind spot: a current cap
  configured inside the car is invisible to the charger and does not trigger the sensor.

## [0.2.8] – 2026-07-11

### Fixed
- **battery_assist: charger stays armed when the battery side stops pushing** — the
  `ev_stop` branch of `ev_solar_charge_mode_control` (and the mode-entry cleanup) no longer
  turn off `switch.peblar_ev_charger_charge` while in `battery_assist` mode. In that mode
  the home battery system is the authority on when to push power; excess collapses to ~0
  whenever it abstains — e.g. HBA's new "waiting for EV" state while the charger needs a
  tag scan or the car paused itself. Disarming the charger there created a deadlock:
  the car could never resume drawing, so the battery side could never see it resume.
  Observed live 2026-07-11 22:17 (charge switch turned off 3 min into a waiting period).
  An armed charger with a suspended car draws 0 W; assist end still stops the charger via
  the generic mode control when `ev_charging_mode` returns to `none`.

## [0.2.7] – 2026-07-11

### Fixed
- **Home battery discharge no longer masquerades as solar surplus** —
  `sensor.ev_grid_excess_power` now subtracts the battery *discharging* component in every
  mode except `battery_assist`. Previously only the charging component was handled (added
  back), so when a home battery system exported to the grid (e.g. a sell-at-expensive-hours
  strategy), the export was indistinguishable from solar surplus and could start/sustain a
  solar-mode charging session on battery power. Verified against production recorder data:
  battery-only discharge briefly pushed the old excess above the 1380 W start threshold and
  flipped `ev_optimal_charging_phase_mode` out of `stop`; the corrected value stays negative.
  In `battery_assist` mode the subtraction is bypassed (consuming battery power is the point),
  confirmed byte-identical against a recorded full assist session. The corrected excess always
  converges to the true solar surplus (production − house load), even when the battery system
  regulates grid power with a PID.
- **Sign convention documentation** — the `ev_home_battery_power_entity` helper comment and
  the dashboard settings markdown said "positive = charging"; the code (and the suggested
  `sensor.hba_total_battery_power`) use positive = discharging. Docs corrected to match the
  code.

## [0.2.6] – 2026-06-20

### Added
- **Unexpected charging detection** — new `binary_sensor.ev_unexpected_grid_charging` (delay_on 5 min) detects two anomaly classes: (1) charger drawing > 300 W while `ev_charging_mode` is `none`; (2) charger drawing > 300 W with > 500 W grid import while in `solar` or `battery_assist` mode (control loop not regulating). Suppressed automatically when `input_boolean.ev_manual_override` is on. Two new automations: `ev_notify_unexpected_grid_charging` fires push + persistent HA notification on turn-on (persistent stays until manually dismissed, for overnight visibility); `ev_notify_unexpected_grid_charging_resolved` fires push-only when the condition clears (skipped if manual override caused the clearance).

## [0.2.5] – 2026-06-20

### Fixed
- **Charger not stopping after solar mode cleanup** — `number.peblar_ev_charger_charge_current_limit_ma` now has the same write guard as `number.peblar_ev_charger_charge_limit`: it refuses to write when `switch.peblar_ev_charger_charge` is off. Previously, `ev_solar_dynamic_power_control` wrote 6000 mA every 3 s (correct ramp-down during the stop countdown), but after `ev_solar_charge_mode_control` called `switch.turn_off` the same 3-second tick immediately overwrote the 0 on Modbus register 40000 with 6000, re-enabling charging. The guard closes this race without affecting the ramp-down behaviour.

## [0.2.4] – 2026-06-13

### Added
- **Battery assist phase recovery** — new `ev_battery_assist_phase_recovery` trigger detects
  when `battery_assist` mode is active but the charger is off due to a temporary phase-mode
  `stop`. Re-evaluates phase mode and restarts the charger once conditions allow, without
  waiting for the next full mode cycle.
- **Notification automations list on dashboard** — auto-entities card in the dashboard now
  lists all `automation.ev_notify_*` entries for easy enable/disable.

### Changed
- **`ev_solar_viable` threshold lowered to 100 W** and decoupled from
  `ev_solar_min_charge_threshold_w` — the viable gate now uses a fixed 100 W floor so it
  opens as soon as panels produce anything meaningful, independent of the minimum charge
  current setting.

### Fixed
- **Notify validator** — rewritten to use `startswith('notify.')` prefix check instead of
  a states lookup; fixes false positives and corrects `available_notify_entities` attribute.
- **Logbook/recorder exclusions** — high-frequency control-loop entities
  (`automation.ev_solar_dynamic_power_control`, `number.peblar_ev_charger_charge_current_limit_ma`,
  `sensor.ev_grid_excess_power_smoothed`) excluded from logbook and/or recorder to reduce
  database noise (~44 K writes/day for smoothed sensor alone). `install.sh` updated with
  `modbus` logbook domain exclusion reminder.

## [0.2.3] – 2026-06-10

### Added
- **Battery assist fast start** — new `ev_battery_assist_entry` trigger fires 30 s
  after `battery_assist` mode is entered and starts the charger immediately based on
  the current phase mode, bypassing the normal 2–4 minute `ev_1p`/`ev_3p` delays.
  No-op if the charger is already on or if phase mode is still `stop`.

## [0.2.2] – 2026-06-09

### Fixed
- **Home battery power sign correction** — `ev_grid_excess_power` adds back battery
  charging power to recover true solar surplus when a home battery is configured. The
  formula used `[batt_power, 0] | max`, which assumed positive = charging. Corrected to
  `[-(batt_power), 0] | max` to match the actual convention of
  `sensor.hba_total_battery_power` (positive = discharging). Previously, battery assist
  discharge inflated `ev_grid_excess_power`, causing the EV to import from grid.

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
