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
of whole amps). Before installing, enable Modbus on the charger:

1. Open the Peblar web interface (browse to its IP address on your LAN).
2. Go to **Settings → Connectivity → Modbus API** and enable it.
3. Note the charger's IP address or hostname — you will need it during setup.

See `MODBUS-README.md` for the full installation procedure, including the
required order of steps (remove the official REST integration first, then
install and configure the Modbus package).