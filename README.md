# ha-smart-ev-charging

## Information
EV charging project using Home Assistant, Peblar &amp; Dynamic Tarifs. Private-focussed use (not adapted for public use)

This project is for personal use only. Not intended for public use but feel free to re-use in your own project. Still work in progress.

Needs work for public use, but might be done later.


## Requirements
Probably incomplete but it's a start:
- Solar integration (for solar charging, entities that show current power-use)
- P1-meter (preferably with quick updates)
- Peblar EV charger with **Modbus TCP enabled** (see below)
- Frank Energie integration (default price source) or Entso-e — see `input_text.ev_price_entity`

### Enabling Modbus on the Peblar charger

This project controls the Peblar via Modbus TCP instead of the official REST
integration, which gives milliamp-precision current control (1 mA steps instead
of whole amps). Before installing, configure the charger:

1. Open the Peblar web interface (browse to its IP address on your LAN).
2. Go to **Settings → Connectivity → Modbus API**, enable it, and set the
   access level to **Read/Write** — read-only is not sufficient for control.
3. Optionally set the **REST API** to read-only (same page) so it cannot
   interfere if the official HA integration is ever re-added by accident.
   Note: the official Peblar HA integration will re-enable the REST API when
   it is active, so removing it from HA is the more reliable safeguard.
4. Note the charger's IP address or hostname — you will need it during setup.

See `MODBUS-README.md` for the full installation procedure, including the
required order of steps (remove the official REST integration first, then
install and configure the Modbus package).

## Dynamic prices and window charging

All price logic reads one sensor, `sensor.ev_energy_prices_data`. It takes the `prices`
attribute of the sensor named in `input_text.ev_price_entity` (Advanced settings → Price data)
and turns it into a sorted list of slots (`slots: [{ts, price}]`, `slots_per_hour`).

- **Source:** Frank Energie (`{from, till, price}`) or ENTSO-E (`{time, price}`), hourly or
  15-minute. Empty = `sensor.frank_energie_prices_current_electricity_price_all_in`. Use the
  all-in sensor if you want the max price to be an all-in price. The cheapest-hours ranking is
  the same for all-in and market prices.
- **Outages:** when the source has no prices, the slots that have not ended yet are kept
  (`stale: true`). Slots are fixed timestamps and are never reused for another day. After an
  hour you get a notification.
- **Cheapest hours** (window charging + `ev_dynamic_tariff_optimization`): picks the cheapest
  ⌈hours needed × slots per hour⌉ slots between now and the window end. The plan is shown as a
  chart and summary under **Window Charging** on the main view.
- **Max price** (`ev_window_max_price_enabled`, `ev_window_charging_max_price`, default 0.32,
  **off by default**): while on, window and cheapest charging only run in slots at or below the
  limit. Without tariff optimisation that means "charge whenever it is cheap enough".
- **Prices not known yet:** next-day prices are published around 13:15 (Frank Energie). Until
  then, a window that ends the next morning is only partly priced, and the selection only
  compares the known part. `binary_sensor.ev_window_prices_known` shows this. If prices are
  still missing after 14:00, `binary_sensor.ev_window_prices_late` turns on and you get a
  notification.

## Using with a home battery (HBA)

Works on its own; with [Home Battery Assistant](https://github.com/Dennis-Q/marstek-venus-rs485-hba)
(HBA) the two exchange a few entities. Set these under Advanced settings → Power entities:

| EV helper | HBA entity | Effect |
|---|---|---|
| `ev_home_battery_power_entity` | `sensor.hba_total_battery_power` | Solar mode counts battery charging as surplus for the car; battery discharge (e.g. selling) never counts as solar |
| `ev_home_battery_assist_active_entity` | `binary_sensor.hba_battery_assist_active` | HBA *Timed EV charge*: the car charges from the batteries (battery_assist mode) |
| `ev_home_battery_priority_entity` | `binary_sensor.hba_batteries_before_ev` | HBA *Charge alongside EV* below its *Batteries first* reserve: the batteries get the solar surplus first, the car what is left |

In the other direction HBA reads `binary_sensor.ev_is_charging` and
`binary_sensor.ev_charger_saturated` (both set in HBA's EV Charge view). For HBA's per-phase
limits you can define `sensor.ev_charger_power` (or `_l1`..`_l3`) in HBA's `hba_config.yaml` from
`sensor.peblar_ev_charger_power` / the Peblar per-phase Modbus sensors. The Peblar's own load
balancing keeps protecting the grid connection; HBA's main fuse limit only limits the batteries.

## Installation

Run this from your Home Assistant `/config` directory (e.g. via the SSH add-on):

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/ha-smart-ev-charging/main/install.sh)
```

To install from the `dev` branch or a specific release tag:

```sh
EV_VERSION=dev bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/ha-smart-ev-charging/dev/install.sh)
EV_VERSION=v1.0.0 bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/ha-smart-ev-charging/main/install.sh)
```

Fetch `install.sh` from the **same ref** you are installing (note `dev/install.sh` above, not
`main/install.sh`). `EV_VERSION` selects which ref the *package files* come from, but the
installer itself is whatever you piped into bash — so mixing them runs an older installer
against newer content. That matters whenever a release adds a package file: the installer
carries the list of files to download, so an older one silently skips the new file and leaves
you with a half-updated install. Release tags are self-consistent, so `main/install.sh` is
correct for those.