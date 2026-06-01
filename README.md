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
- Entso-e integration (and in Dashboard also Frank Energie)

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

## Installation

Run this from your Home Assistant `/config` directory (e.g. via the SSH add-on):

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/ha-smart-ev-charging/main/install.sh)
```

To install from the `dev` branch or a specific release tag:

```sh
EV_VERSION=dev bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/ha-smart-ev-charging/main/install.sh)
EV_VERSION=v1.0.0 bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/ha-smart-ev-charging/main/install.sh)
```