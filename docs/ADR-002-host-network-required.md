# ADR-002: `host_network: true` is mandatory for BlueZ addons

**Status**: Accepted (after failed attempt to drop it)  
**Date**: 2026-04-17  
**Release**: `haos-sbfspot` 2026.4.17.9 (revert of 2026.4.17.6–8)

## Context

The addon ran with `host_network: true` (inherited from upstream) which exposes the host's network namespace to the container. This is a security concern — if the addon is ever compromised, the attacker has access to every network interface, every local host, every MQTT broker on 0.0.0.0.

We attempted in `2026.4.17.6` to drop to `host_network: false` on the theory that:

- MQTT reaches `core-mosquitto.local.hass.io` via supervisor's internal docker network. That works fine without host netns.
- BlueZ management happens via D-Bus. `host_dbus: true` provides that.
- Nothing else in the addon needs host-level network.

## Decision

**Keep `host_network: true`.** Do not drop it.

## Why dropping it failed

Live deployment on `2026.4.17.8`:

```
Connecting to 00:80:25:21:32:35 (1/10)
Connecting to 00:80:25:21:32:35 (2/10)
...
Connecting to 00:80:25:21:32:35 (10/10)
CRITICAL: bthConnect() returned -1
```

Every poll failed at the BT connect step. Root cause: **BlueZ uses `AF_BLUETOOTH` raw sockets that bind to `hci0`, and `hci0` is a host-level interface that lives in the host network namespace**. Without host netns, the container sees no `hci*` devices, so `socket(AF_BLUETOOTH, SOCK_RAW, BTPROTO_HCI)` returns an fd bound to nothing useful.

`host_dbus: true` provides access to the BlueZ management API (scanning, pairing, device enumeration) but NOT to raw HCI sockets. SBFspot (and any BT Classic stack using AF_BLUETOOTH) needs the raw socket path.

We reverted in `2026.4.17.9` after ~15 minutes of downtime.

## Implications

- The attack surface from `host_network: true` is real but cannot be mitigated at the netns boundary without breaking BT.
- Hardening must happen **inside** the container: capability drops, AppArmor profile restrictions, filesystem mount constraints.
- Specifically: drop `CAP_NET_ADMIN`, `CAP_SYS_ADMIN` if SBFspot doesn't need them. Keep `CAP_NET_RAW` for HCI sockets. TBD in ADR-004 (AppArmor tightening, future release).

## Alternatives considered

- **USB pass-through of the BT dongle instead of host_network**: would give the container direct access to the HCI device without host netns exposure. Would require changes to the supervisor USB layer and the BlueZ initialization inside the container — significantly more work. Reserve as a v4 option.
- **Socket bind via supervisor helper service**: no such helper exists today.
- **Custom `bluez` D-Bus bridge**: too invasive.

## Code references

- `haos-sbfspot/config.yaml` — `host_network: true` with a block comment referencing this ADR
- Related: `ADR-004-apparmor-tightening.md` (placeholder, v4 roadmap)
