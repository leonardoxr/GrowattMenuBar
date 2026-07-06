# GrowattMenuBar

GrowattMenuBar is a macOS menu bar app for reading a Growatt inverter locally through a ShineWiFi-X datalogger that exposes Modbus TCP.

The app is local-first and read-only. It does not use Growatt cloud credentials, does not call the ShinePhone API, and only sends Modbus read-input-register requests to the configured LAN host.

## Features

- Menu bar AC output wattage
- Expanded popover with PV, AC, PV1, PV2, daily energy, total energy, grid voltage/frequency, and inverter temperature
- Short local power history chart
- Configurable host, port, Modbus unit id, polling interval, and inverter capacity
- Conservative polling for ShineWiFi-X gateways

## Requirements

- macOS 14 or newer
- Swift 6 / Xcode command line tools to build from source
- A Growatt-compatible inverter reachable through Modbus TCP
- A ShineWiFi-X or similar gateway on the same LAN with TCP port `502` open

Known working discovery pattern:

```text
Mac/Home Assistant: 192.168.31.x
ShineWiFi-X:        192.168.31.5
Gateway/router:     192.168.31.1
Modbus TCP:         192.168.31.5:502
Unit id:            1
```

The datalogger may stay connected to Growatt cloud. This app reads locally and does not change the cloud server settings.

## Build And Run

Run from source:

```bash
swift run
```

Build a release `.app` bundle:

```bash
./Scripts/build-app.sh
open dist/GrowattMenuBar.app
```

## Configuration

Open the menu bar popover and expand `Connection`.

Default values:

```text
Host:     192.168.31.5
Port:     502
Unit:     1
Poll:     10 seconds
Capacity: 6000 W
```

If the host changes, prefer setting a DHCP reservation on your router for the datalogger MAC address instead of relying on random DHCP leases.

## Network Notes

The Mac and datalogger must be able to talk on the same LAN. Guest WiFi, AP isolation, client isolation, or separated IoT VLANs usually block local Modbus TCP even when Growatt cloud upload still works.

2.4 GHz vs 5 GHz is not the key issue. The datalogger can stay on 2.4 GHz while the Mac uses 5 GHz, as long as both are bridged to the same LAN/subnet and `host:502` is reachable.

## Safety

This app intentionally implements only Modbus function `04` read-input-register requests. It does not write inverter or datalogger settings.

Still, use it at your own risk. Solar inverters and dataloggers are electrical equipment; do not change wiring or open equipment unless qualified.

## Privacy

This repository is safe to publish publicly:

- No Growatt usernames or passwords
- No cloud API tokens
- No inverter or datalogger serial numbers
- No vendor account data

Only private LAN defaults such as `192.168.31.5` are included, and they are configurable.
