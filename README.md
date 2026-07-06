# GrowattMenuBar

GrowattMenuBar is a lightweight macOS menu bar app for local, near-realtime Growatt inverter monitoring through Modbus TCP.

It was built around a Growatt `MIN ... TL-X/TL-X2` style inverter with a `ShineWiFi-X` datalogger exposing TCP port `502`, but the app should work with other Growatt setups that expose the same Modbus input registers.

The app is local-first and read-only:

- No Growatt cloud credentials
- No ShinePhone API login
- No inverter or datalogger write commands
- Only Modbus function `04` read-input-register requests

## What It Shows

- Menu bar AC output, for example `AC 1.55 kW`
- Expanded popover with AC, PV, PV1, PV2, daily generation, lifetime generation, grid voltage/frequency, and temperature
- AC power history chart
- Configurable host, port, Modbus unit id, polling interval, and inverter capacity

## PV vs AC

- `PV` is the DC power coming from the panels into the inverter.
- `PV1` and `PV2` are the two panel strings / MPPT inputs.
- `AC` is the usable AC power leaving the inverter after conversion.
- `PV` is normally a little higher than `AC` because the inverter has conversion losses.

For the menu bar, the app shows `AC` because that is the practical produced output.

## Requirements

- macOS 14 or newer
- Swift 6 / Xcode command line tools to build from source
- A Growatt inverter reachable through a Modbus TCP gateway
- A ShineWiFi-X, ShineWiLan-X2, or similar datalogger on the same LAN
- TCP port `502` reachable from the Mac

Known working pattern:

```text
Mac:              192.168.31.x
Datalogger:       192.168.31.5
Router/gateway:   192.168.31.1
Modbus TCP:       192.168.31.5:502
Modbus unit id:   1
```

The Growatt cloud connection can stay enabled. This app reads locally and does not change the datalogger cloud server.

## Setup

1. Put the datalogger on a normal private LAN, not guest WiFi.
2. Prefer 2.4 GHz for the datalogger. Your Mac can use 5 GHz if it is bridged to the same LAN.
3. Prefer DHCP plus a router DHCP reservation for the datalogger.
4. Reserve a stable IP for the datalogger, for example `192.168.31.5`.
5. Confirm the Mac can reach it:

```bash
ping 192.168.31.5
nc -vz 192.168.31.5 502
```

6. Run the app and open the `Connection` section.
7. Set:

```text
Host:     192.168.31.5
Port:     502
Unit:     1
Poll:     10 seconds
Capacity: 6.0 kW
```

If you use static IP on the datalogger instead of DHCP reservation, the fields must match your actual LAN:

```text
IP address:       192.168.31.5
Gateway settings: 192.168.31.1
Subnet mask:      255.255.255.0
DNS:              192.168.31.1 or 8.8.8.8
```

After changing advanced network settings in ShinePhone hotspot mode, return to the WiFi configuration screen, enter the SSID/password, and tap the app's configure/apply button. Just saving the advanced screen may not apply the settings to the active WiFi connection.

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

The app is a menu bar accessory. It will not show a Dock icon.

## Common Problems

### Growatt Cloud Works, But Local App Cannot Connect

This usually means LAN access is blocked even though internet access works.

Check for:

- Guest WiFi
- AP isolation
- Client isolation
- IoT VLAN isolation
- Different subnets, such as Mac on `192.168.33.x` and datalogger on `192.168.31.x`

The Mac must be able to connect directly to `datalogger-ip:502`.

### 2.4 GHz vs 5 GHz Confusion

The datalogger normally needs 2.4 GHz WiFi. The Mac can be on 5 GHz if both radios are bridged to the same LAN/subnet.

Working:

```text
Mac on 5 GHz:       192.168.31.72
Datalogger on 2.4:  192.168.31.5
Gateway:            192.168.31.1
```

Not working:

```text
Mac:         192.168.33.145
Datalogger:  192.168.31.5
```

### Port 502 Is Closed

Possible causes:

- Wrong IP address
- Datalogger still in hotspot/config mode
- Datalogger not on the same LAN
- Modbus TCP not enabled/supported by that firmware/model
- Router isolation blocks device-to-device traffic

Check:

```bash
arp -a
ping <datalogger-ip>
nc -vz <datalogger-ip> 502
```

### Connection Closed Before Response / Timeouts

The ShineWiFi-X Modbus gateway can be sensitive. Avoid aggressive polling or large register reads.

This app intentionally uses small register blocks and defaults to a 10 second poll interval. If you still see intermittent timeouts:

- Keep poll interval at 10 seconds or higher
- Exit hotspot/config mode
- Restart the datalogger
- Avoid running multiple Modbus clients against the dongle at the same time

### WiFi SSID Or Password Problems

Some datalogger setup flows are picky about SSID/password parsing. If configuration silently fails, test with a simple 2.4 GHz SSID:

```text
SSID:     Solar
Password: Solar123456
Security: WPA2-Personal
```

Avoid special characters, emoji, accents, quotes, and very long passwords while debugging.

### Menu Value Does Not Match PV Gauge

The menu shows `AC`. `PV` is panel-side DC input, and can be higher than `AC`.

If you want usable produced power, use `AC`.

## References

These are the docs and community notes that helped validate the setup:

- [Growatt technical whitepaper page](https://community.growatt.com/white-paper?page=5) - official Growatt page listing `Single Device Control via Growatt Modbus TCP (ShineWiLan-X2)`.
- [Growatt Modbus TCP whitepaper PDF](https://community.growatt.com/upload/file/Single_Device_Control_via_Growatt_Modbus_TCP_%28ShineWiLan-X2%29.pdf) - official PDF describing the Modbus TCP gateway architecture.
- [Single Device Control via Growatt Modbus TCP (Scribd mirror)](https://www.scribd.com/document/830061017/Single-Device-Control-via-Growatt-Modbus-TCP) - user-provided reference used during setup. Treat it as a mirror, not the canonical source.
- [Growatt ShineWiFi-X / ShineWiFi-S configuration instructions](https://growatt9160.zendesk.com/hc/en-us/articles/35782430992537-Configuration-Instructions-for-ShineWiFi-X-ShineWiFi-S) - hotspot/configuration flow.
- [Growatt MIN 2500-6000TL-X/X2(Pro) product page](https://en.growatt.com/products/min-2500-6000tl-x-x2%28pro%29) - inverter family reference.
- [PLCHome/growatt README](https://github.com/PLCHome/growatt/blob/master/README.md) - community API client notes, datalogger register references, and warning about datalogger writes.
- [Home Assistant Growatt interval discussion](https://community.home-assistant.io/t/growatt-server-integration-interval/207840/9) - community notes around datalogger interval behavior.
- [Grott discussion: ShineWiFi-X report frequency](https://github.com/johanmeijer/grott/discussions/93) - community notes around ShineWiFi-X interval/register behavior.

## Safety

This app is read-only, but solar equipment can be dangerous. Do not open, wire, or modify inverter hardware unless qualified.

The code intentionally does not implement Modbus write functions.

## Privacy

This repository is safe to publish publicly:

- No Growatt usernames or passwords
- No cloud API tokens
- No inverter or datalogger serial numbers
- No vendor account data

Only private LAN defaults such as `192.168.31.5` are included, and they are configurable.
