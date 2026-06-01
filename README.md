# ha-smart-ev-charging

## Information
EV charging project using Home Assistant, Peblar &amp; Dynamic Tarifs. Private-focussed use (not adapted for public use)

This project is for personal use only. Not intended for public use but feel free to re-use in your own project. Still work in progress.

Needs work for public use, but might be done later.


## Requirements
Probably incomplete but it's a start:
- Solar integration (for solar charging, entities that show current power-use)
- P1-meter (preferably with quick updates)
- EV-charger Peblar and active integration (official via restAPI)
- Entso-e integration (and in Dashboard also Frank Energie)

### Peblar entities to enable

The Peblar integration ships these entities **disabled by default** — enable
them in *Settings → Devices & Services → Peblar → Entities*:

- `sensor.peblar_ev_charger_voltage_phase_1`
- `sensor.peblar_ev_charger_voltage_phase_2`
- `sensor.peblar_ev_charger_voltage_phase_3`

The charging-amps templates use the live phase voltages when available
(falling back to 230 V / 690 V if the sensors are missing or unreachable),
which gives slightly more accurate amp targets than a hardcoded 230 V — your
mains will typically be 220–245 V, and individual phases can differ by several
volts.

Enabling these is also useful for diagnostics:

- `sensor.peblar_ev_charger_current_phase_1/2/3` — confirms which phase the
  car is actually drawing from when the charger is in single-phase mode