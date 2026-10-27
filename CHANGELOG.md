# Changelog

All notable changes to this project will be documented here.

## [0.2.19] – unreleased

### Added
- **Up to three cars** instead of the hard-wired Skoda Elroq (with Mik3yZ). New package
  `packages/ev/ev_vehicles.yaml` and a **Cars** view. Per car: name, battery capacity, max charge
  power, *charges on 1 phase*, and the entities of its integration — SoC sensor, charge-limit
  number, start charging (switch or button), connected sensor; an empty field skips what needs
  it. The logic reads the active car through `sensor.ev_active_car`, `sensor.ev_car_soc`,
  `sensor.ev_car_target_soc`, `sensor.ev_car_expected_limit`, `sensor.ev_car_battery_capacity`,
  `sensor.ev_car_max_power`, `binary_sensor.ev_car_single_phase`,
  `binary_sensor.ev_car_reports_connected`.
  - Car 1 is always on; with only car 1 nothing about choosing a car appears. With more cars:
    car selector on the main view, **"which car?"** notification at plug-in (no answer = the
    current car stays), and a **phase check** that asks (never switches) when only L1 draws
    while a 3-phase car is selected.
  - **Guest**: car 2/3 without a SoC sensor — no car control, the charger is steered alone.
    No window charging (no SoC, so no hours needed), only force and solar. Selecting a guest
    (dashboard or notification) turns on a one-time force charge; turning it off and solar on
    is up to the user. When a guest unplugs the last own car becomes active again. The Cars view
    hides battery capacity and max power for a guest (only used with a SoC sensor).
  - **1-phase cars** (e.g. Dacia Spring, Mik3yZ 7f84856): the charger stays forced single-phase
    in solar, force and window, so solar gets the whole surplus instead of a third of it.
  - **Car limit writes are rounded and clamped** to the number's min/max/step (Renault: 55–100
    in steps of 5); the limit check compares with that value, so it never retries an
    unreachable limit.
  - **MySkoda prefill**: while car 1's SoC field is empty, the MySkoda entities are filled in at
    start (waits up to 5 minutes for the integration), so an existing install behaves as before.
  - `binary_sensor.ev_car_setup_missing` + dashboard banner when car 1 has no SoC entity or a
    configured one does not exist.
  - Removed: `input_number.ev_battery_capacity_kwh` (now per car; 60 kWh / 11 kW by default).
  - `script.ev_notify_dispatch` takes optional mobile-app `actions`.

### Fixed
- **No more 16 A bursts at solar starts and phase switches.** `switch.peblar_ev_charger_charge`
  wrote `charge_limit_desired` (16 A after any window/force session) on every `turn_on`, also
  when already on — replacing the setpoint the solar loop had just written until the next 3-s
  cycle (prod 2026-10-25 09:31: 3.4 kW on one phase; at a 1P→3P step-up up to 11 kW). Now:
  - `turn_on` does nothing while the switch is on (unless a stop is in progress);
  - every solar / battery-assist start sets `charge_limit_desired` to its own start value
    first, because the mA write is refused while the switch is off;
  - force start sets the A limit to 16 (which sets `charge_limit_desired`) instead of an mA
    value the charger refuses while off (Mik3yZ 7f84856).
- **1-phase car: correct hours needed.** `sensor.ev_car_max_power` caps a 1-phase car at a
  third of the charger (3.7 kW on an 11 kW charger); it used the full 11 kW, so window/cheapest
  planned about 3× too few hours.
- **The running cheapest slot is kept.** As the SoC rises and hours needed shrinks, re-sorting
  by price could drop the slot that was charging for a cheaper later one — charging stopped
  mid-slot and the rest was bought later (prod 2026-10-13). Now only future slots are dropped.
- **Max price in the plan:** with the max price limit on, slots above it are no longer selected
  (or shown green on the chart) and do not count for *sufficient known hours* — they never
  charged anyway.
- **Price charts start at 0** (soft minimum; lower only with negative prices). They started at
  the lowest price, so e.g. €0.28 looked like nothing next to €0.73.
- **EV notifications switch now covers every EV notification.** `script.ev_notify_dispatch`
  checks `input_boolean.ev_notifications_enabled` itself; 12 automations (force charge, limit
  corrected, charging complete, price data, unit mismatch, …) used to ignore it. New field
  `critical: true` sends anyway — only the *charger failed to stop* notification uses it.
- **A wrong notify action no longer aborts the automation that notifies.** The notify call runs
  in `script.ev_notify_send`, started without waiting; a typo or removed phone fails only that
  run (visible in its trace). `continue_on_error` does not cover an action that does not exist.
  The dispatch also applies its field defaults itself (HA only uses them as UI hints) and runs
  in parallel, so simultaneous notifications are no longer dropped.
- **Notify target check:** an empty helper is fine again (notifications go to persistent
  notifications, as documented) and any `notify.*` action is accepted (`notify.notify`,
  `notify.telegram`, …). Still flagged: not `notify.<name>`, or the id of a notify *entity*
  instead of an action.
- **"EV Charging Complete" only when the SoC rises to the limit** while charging (or within
  15 minutes after). It also fired when the limit dropped below the SoC — e.g. 75 % after solar
  and a 60 % window limit — without any charging.
- **Main view no longer shows Skoda entities**: the Skoda range is gone from *EV Charging
  Status* (it stays on the Elroq view), and *Car Charging On/Off* is now a *Car — start
  charging* button for the active car (`script.ev_car_start_charging`, switch or button).
- `number.peblar_ev_charger_charge_limit`: `reg / 1000 | round` rounded the 1000, not the result,
  so the decimals were accidental. Now deliberately 2 decimals (e.g. 6.35 A) so the solar
  regulation stays visible; setting it still takes whole amps. Comment now names the register it
  really reads (40000).
- `dashboard.yaml`: header toggles off on *EV Charging Settings* and *Charge Control* — one tap
  switched every boolean on the card (manual override, permanent force, all modes) at once.
- Notification automations list (Advanced settings) now also shows the manual-override
  reminder, *which car?* and the phase check.
- `.gitattributes` keeps `install.sh` LF on Windows checkouts.
- README: `sensor.p1_meter_power` is required (defined by HBA, template for installs without
  it); `script.ev_select_car` is the way for automations to choose a car.
- **`sensor.ev_expected_charging_limit` is never empty** (from Mik3yZ, 6789b4c): it follows
  `sensor.ev_charging_mode`; with no active mode it is the car's own limit, so — as before —
  nothing is corrected then. Ends the recurring "invalid sensor state" error. New attribute
  `limit_source` (the mode, or `car`).
- **Plug-in while no mode applies disarms the charger** (Mik3yZ, from 7f84856): the
  `connected` trigger of `ev_generic_charging_mode_control` now also turns the charge switch
  off when `sensor.ev_charging_mode` is `none`, in case it was left on.
- **Dashboard banners are always on top** (both dashboards): all banners sit in one vertical
  stack as the first card. Hidden banner cards still took a masonry slot, so a visible banner
  could land in the middle column on desktop instead of at the top.
- `ev_validate_charging_limit` only compares when both limits are numbers (it used to raise a
  template error on an empty expected limit).

## [0.2.18] – unreleased

### Added
- **Charging plan on the dashboard** (Solar Charging view, next to Window Charging): an
  apexcharts column chart of the next 36 h of prices from `sensor.ev_energy_prices_data` with
  the selected slots in green, plus a summary — selected slots with price, hours needed, and
  until when prices are known.
- **`binary_sensor.ev_window_prices_known`** — on when the price data reaches the end of the
  charging window; attributes `known_until`, `window_end`, `missing_hours`. Informational: it
  does not change charging yet. Motivation (prod 2026-10-23): with the window at 08:00–07:00
  the selection ran on today's prices only — ENTSO-E published tomorrow's at 22:24 — so it
  charged at €0.12–0.16 midday and evening while the night was €0.02.
- **`binary_sensor.ev_window_prices_late`** (device_class problem) — on when it is after 14:00
  and the window is still not fully priced. Frank Energie publishes the next day at 13:15
  (prod, every day 2026-10-21..23), so before 14:00 an incomplete window is normal for a window
  that ends the next morning; the dashboard only says "expected around 13:15" then.
- **`ev_window_prices_late_notification`** — push + persistent notification when that sensor
  has been on for 5 minutes while window charging with tariff optimisation is on; the
  persistent notification clears once the window is fully priced.
- **Home battery priority — `input_text.ev_home_battery_priority_entity`.** Optional
  binary_sensor from the home battery system that is on while the battery should get the solar
  surplus first. While on, `ev_grid_excess_power` no longer adds the battery's charging power
  back, so the EV only gets what the battery leaves over. Empty (the default) keeps the old
  behaviour. HBA: `binary_sensor.hba_batteries_before_ev` (Charge alongside EV, below the
  *Batteries first* kWh reserve) — without it EV solar mode took the surplus HBA was holding
  for the batteries.

### Changed
- **Installer shows the commit** for a branch install (`EV_VERSION=dev` / `main`): branch, short
  hash, date and commit message, like the HBA installer. Every file is then downloaded from that
  exact commit — by branch name, raw.githubusercontent.com caches files for a few minutes, so one
  run could mix two commits. Release tags are shown as before.

### Fixed
- **Entity fields that were never filled in no longer show `unknown`** — automation
  `ev_clear_unknown_entity_fields` sets them to empty at start (the logic already treated both the
  same; the dashboard looked broken, e.g. *Price entity* `unknown` while prices were loaded).

### Added (preview)
- **Preview dashboard** `dashboard_preview.yaml` → `lovelace/ev_dashboard_preview.yaml` (installer).
  Dashboard improvements from the 2026-10-25 review land there first; shown once registered under
  `lovelace: dashboards:` (e.g. `ev-preview`, `filename: lovelace/ev_dashboard_preview.yaml`).
  Done there so far: no header toggles on the settings / charge-control cards (one tap switched force
  charge, override, charger and car together), Window Charging as a readable table (yes/no, "Mon
  03:00" instead of true/false and raw timestamps), clear price names (Frank all-in / market,
  ENTSO-E), price source as text, English Frank chart title, Peblar: "Up since", WLAN hidden when
  not used, error/warning rows only when active.

## [0.2.17] – 2026-10-14

### Added
- **Configurable price source — `input_text.ev_price_entity`.** Any sensor with a `prices`
  attribute: Frank Energie (`{from, till, price}`) or ENTSO-E (`{time, price}`), hourly or
  15-minute slots. Empty (the default, so existing installs need no action) means
  `sensor.frank_energie_prices_current_electricity_price_all_in`. **Behaviour change:** the
  cheapest-hours selection used to read ENTSO-E `sensor.average_electricity_price`; it now uses
  Frank Energie unless you set the ENTSO-E sensor here. Ranking is the same for all-in and
  market prices (the difference is close to a fixed markup), so the choice mostly affects the
  max price below and what the dashboard shows.
- **`sensor.ev_energy_prices_data`** — the only place that reads the provider sensor. Its
  `slots` attribute (`[{ts, price}]`, sorted, one entry per timestamp) plus `slots_per_hour`
  are what every window sensor now reads. Same shape as the home battery project's
  `sensor.hba_energy_prices_data`, so the parsing can later become a shared adapter without
  touching consumers. Duplicate timestamps are dropped: Frank Energie appends a second copy of
  today when its tomorrow-fetch fails, which would make the same hour count twice.
- **Price data survives a provider dropout.** When the price sensor has no prices (unavailable,
  not loaded yet after a restart), `sensor.ev_energy_prices_data` keeps the previous slots that
  have not ended yet and sets `stale: true`. Fixes the stop seen on prod 2026-10-13 23:13:
  ENTSO-E went `unavailable` mid-charge, the cheapest list emptied and the mode dropped to
  `none`. Slots are absolute timestamps and only not-yet-ended ones are kept, so old prices are
  never applied to a later day: once the last known slot ends (at most ~35 h), there is no price
  data and cheapest-hours charging stops, as before.
- **`ev_price_data_stale_notification`** — push + persistent notification when the price source
  has given no prices for an hour while tariff optimisation or the max price limit is on; says
  until when prices are still known. Persistent notification clears when prices return.
- **Prefer tariff over solar also works without tariff optimisation** (from Mik3yZ's branch).
  With optimisation off, an active window — every slot at or below the max price, when that
  limit is on — now wins over solar (mode `window`). With optimisation on, nothing changes,
  except that the branch no longer reports `cheapest` while optimisation is off.
- **Window max price** — `input_boolean.ev_window_max_price_enabled` +
  `input_number.ev_window_charging_max_price` (EUR/kWh; `apply_defaults`: 0.32, limit off — opt in, so an expensive night still charges by default) and
  `binary_sensor.ev_window_price_allowed`. While enabled, `window` and `cheapest` only charge
  when the current slot is at or below the limit; it fails closed (no current price ⇒ no
  window charging). Solar, battery assist and force are not affected. The limit is in the
  terms of the configured price sensor — pick the all-in sensor for an all-in limit.

### Changed
- **Cheapest-hours selection works per slot** instead of per hour, so 15-minute prices
  select the right amount of time (⌈hours needed × slots per hour⌉) and
  `ev_is_in_cheapest_window` matches the current slot instead of the current hour prefix.
- **`sensor.ev_cheapest_hours_in_window` state is now the number of selected slots;** the list
  moved to the `slots` attribute (`[{ts, time, price}]`). As a JSON state it hit HA's
  255-character limit on longer charges and went `unknown`.
- **`sensor.ev_charging_debug_info`** — short one-line state; the multi-line summary moved to
  the `details` attribute (same 255-character limit; it adds price source and max-price
  lines).

### Thanks
- Mik3yZ — the max price limit, the Frank Energie switch and the debug-info fix come from their
  `window-charging-max-price` branch, reworked onto the shared price data sensor; the
  prefer-tariff change is theirs as well.

## [0.2.16] – 2026-07-27

### Fixed
- **Charger could sit at the 3-phase floor importing from the grid instead of stepping down**
  (production 2026-07-26 and 2026-07-27). The 3-phase floor is 6 A × 3 ≈ 4.1 kW against a
  1-phase floor of ≈ 1.38 kW, so once surplus falls short, staying in 3-phase costs ~2.7 kW of
  grid import while staying in 1-phase costs ~0. Both step-down paths — `ev_stop` and `ev_1p` —
  require their state to hold for 2 continuous minutes, but when surplus hovers at
  `ev_solar_min_charge_threshold_w` the phase mode flaps `single_phase`↔`stop` every few
  seconds, so neither `for:` ever completes, and `mode: restart` means each flap cancels the
  other's timer. On 2026-07-27 the charger drew 4.1 kW with 2.4–3.0 kW import for 7 minutes and
  was only rescued by a manual force-to-1-phase; on 2026-07-26 an equivalent stall ran 7 minutes
  after a `cheapest`→`solar` handover before `ev_stop` happened to catch it.

  New `leave_3p` template trigger (60 s) fires when the charger is charging, is in 3-phase, and
  the phase mode says it should not be — treating `stop` and `single_phase` as the same
  instruction, since in 3-phase they both mean "step down". It shares the `ev_1p` branch, so the
  charger drops to 1-phase at 6 A and **keeps charging**; `ev_stop` still makes the stop
  decision 2 minutes later, but now from 1-phase where being wrong is nearly free. Deliberately
  asymmetric: leaving 3-phase is expensive and therefore fast, stopping is cheap and stays lazy.
  Also lowers the `battery_assist` floor from 4.1 kW to 1.4 kW while keeping the charger armed.

  Two design points, both learned from prod traces rather than reasoning:
  - It must be a **template** trigger, not `not_to: "three_phase"`. A state trigger's `for:`
    restarts on every state change that matches it, so the `single_phase`↔`stop` flapping would
    reset it indefinitely — the very failure being fixed. A template `for:` requires the
    *result* to hold, which it does across the flapping.
  - `sensor.ev_charging_mode` is repeated **inside the template** even though the automation's
    `conditions:` already gate on it. A template trigger fires once on the false→true edge and
    not again while it stays true, so a gate living only in `conditions:` can be missed
    entirely: on 2026-07-26 the template went true at 17:26:15 mid-`cheapest`, fired and was
    discarded at 17:27:15, and was still true at the 18:00 handover to `solar` — no second edge,
    no trigger. Including the mode makes the handover itself an edge.

  The trigger also requires the charge switch to already be `on`, which keeps it a step-down and
  never a start: without it, sunrise entry into `solar` with the charger still configured
  3-phase from the night before would start charging into no surplus for the 60 s before
  `ev_mode_entry` shut it off again.

  Replayed against recorded prod state, this fires 4× on 2026-07-27 against 5 three-phase
  episodes — 05:36:16 (2 min before the real switch), 12:07:16, 13:46:07 (1 min before), and
  14:30:02 (7 min before the manual rescue) — plus the 2026-07-26 18:01:00 handover that the
  first draft missed.

## [0.2.15] – 2026-07-26

### Changed
- **All notification logic moved to `packages/ev/ev_notifications.yaml`.** Pure file split —
  no entity IDs, unique_ids, automation ids or behaviour changed, so nothing is renamed in the
  entity registry and no reconfiguration is needed. Moved: `ev_notify_dispatch` and
  `ev_notify_test` (scripts), and the nine notification-only automations —
  `ev_notify_target_validation`, `ev_charging_complete_notification`,
  `ev_charger_error_notification`, `ev_notify_charger_alert`, `ev_notify_unexpected_charging`,
  `ev_notify_manual_override_reminder`, `ev_notify_unexpected_grid_charging` and
  `_resolved` (from `ev_generic.yaml`), plus `ev_power_entity_unit_mismatch_notification`
  (from `ev_solar.yaml`). `ev_generic.yaml` drops 377 lines, `ev_solar.yaml` 48.

  Helpers and template sensors stay with their domain rather than following the automations:
  `input_boolean.ev_notifications_enabled`, `input_text.ev_notify_entity_id` and
  `binary_sensor.ev_notify_target_invalid` remain in `ev_generic.yaml`;
  `binary_sensor.ev_power_entity_unit_mismatch` and `ev_p1_unit_mismatch` remain in
  `ev_solar.yaml`. Automations that *act* and merely notify as a side effect also stay put —
  notably `ev_validate_charging_limit`, which corrects the car's charge limit. This mirrors
  `hba_notifications.yaml` in the sibling HBA project, which likewise holds only `automation:`
  and `script:`.

- **`install.sh` ships the new file** (added to `CORE_FILES`). Updating requires an installer
  that knows about `ev_notifications.yaml`: an older one will overwrite `ev_generic.yaml` with
  the stripped version and never fetch the new file, silently removing every notification
  *and* `script.ev_notify_dispatch`, which several non-notification automations call.

- **README: fetch `install.sh` from the ref you are installing.** The dev example now uses
  `dev/install.sh` rather than `main/install.sh`. `EV_VERSION` selects the ref for the package
  *files*, but the installer is whatever was piped into bash — mixing them runs an older
  installer against newer content, which is exactly the failure mode above.

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

## [0.2.12] – 2026-07-24

### Added
- **One-time force charge now ends on disconnect** — `input_boolean.ev_force_charge_once`
  auto-disables when the cable is unplugged, making it truly one-time rather than
  "until the 8-hour timeout." New automation `ev_force_charge_once_disable_on_disconnect`
  triggers on `binary_sensor.ev_is_connected` going `off` for 1 minute (the debounce
  absorbs transient unavailable/unknown reads, which also flip that sensor off), turns
  the boolean off, and notifies. The 8-hour timeout and reach-limit auto-disables remain
  as backstops. Permanent force charge is unaffected.

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
