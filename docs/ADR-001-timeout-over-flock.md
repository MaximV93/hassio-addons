# ADR-001: `timeout -s KILL` over `flock -n` for overlap prevention

**Status**: Accepted  
**Date**: 2026-04-17  
**Release**: `haos-sbfspot` 2026.4.17.2  

## Context

Upstream `habuild/hassio-addons/haos-sbfspot` hardcoded a 5-minute cron for SBFspot polling. SBFspot runs typically take 20–40 seconds (Bluetooth session setup + one-shot query). At 5-min polling, overlap is unlikely but not impossible.

The [powerslider fork](../FORK.md) adds configurable polling via `PollIntervalDay` (minimum 1 minute). At 1-min polling, two failure modes become possible:

1. **Legitimate overlap** — an SBFspot run takes >60 seconds and the next tick fires while the previous is still running. BusyBox cron doesn't serialize cron entries, so both run concurrently, both try to open the same BT session, both fail.
2. **Runaway hang** — SBFspot hangs after `Logon OK` (observed: 8+ minutes with MIS mode + 3 devices on marginal BT signal). Every subsequent tick stacks another runaway process; container eventually OOMs or BT stack chokes.

## Decision

Wrap every cron-invoked SBFspot call in `timeout -s KILL N`, where N is derived from polling interval (or explicit user override via `SBFspotTimeoutSec` addon option).

Do **not** use `flock -n` for serialization.

## Rationale

The first instinct (and our initial implementation in v1, release `2026.4.17.1`) was `flock -n /run/sbfspot.lock SBFspot ...` — non-blocking, skip if lock held. Textbook overlap prevention.

In production this made things **worse**:

1. `@reboot` SBFspot run acquires the lock and hangs.
2. Every `*/1 6-22 * * *` tick after that tries `flock -n`, fails to acquire, exits silently with code 1.
3. Polling appears to stop completely — no errors in the log, no publishes to MQTT, no HA sensor updates.
4. The hang is invisible to the user because flock's silent-exit hides it behind the "working as intended" mask.

We observed exactly this on the live deployment: zolder inverter sensor timestamp froze at 00:33 UTC for 6+ hours while the addon appeared healthy.

`timeout -s KILL N` flips the failure mode:

- Each tick has a fresh slate, no shared state.
- A hang is bounded by N seconds (we default to `PollIntervalDay * 60 - 10`).
- After timeout, the process is `SIGKILL`ed; next tick starts normally.
- Exit code 137 (SIGKILL) or 124 (timeout) is distinguishable from "success" or "sbfspot-error", so our wrapper script records it and the heartbeat publisher surfaces it as `sensor.sbfspot_last_run_status = hang` + increments `sensor.sbfspot_hang_count`.

Cost: a small window of potential overlap if a run takes EXACTLY as long as the poll interval minus buffer. In practice this is rare, and if both overlapping runs fail, the next tick self-heals.

## Alternatives considered

- **`flock -w <seconds>`** (blocking with timeout): queues the subsequent run, delaying it. Cron expects quick returns; a delayed job blocks crond's slot rotation. Rejected.
- **`flock -n` + a sidecar watchdog killing hung processes**: two moving parts, harder to reason about. Rejected.
- **In-process locking via SBFspot C++**: requires upstream change. Out of scope.
- **Serialize via cron itself** (chaining with `&&`): BusyBox cron doesn't support dependencies between entries. Rejected.

## Consequences

- Every hang is observable (`sensor.sbfspot_hang_count` monotonically increasing).
- Very marginal BT signals that genuinely need >50 seconds may lose data at 1-min polling. Mitigation: user raises `SBFspotTimeoutSec` override and simultaneously slows `PollIntervalDay` to 2+.
- If SBFspot's hang cause is ever root-caused (upstream fix or config workaround), this ADR can be revisited.

## Code references

- `haos-sbfspot/rootfs/etc/cont-init.d/01-generate-crontab.sh` — generates crontab lines with `timeout -s KILL`
- `haos-sbfspot/rootfs/usr/bin/sbfspot/run-sbfspot.sh` — wraps every SBFspot invocation, records exit code, emits `HANG` banner on 137/124
- `haos-sbfspot/rootfs/usr/bin/sbfspot/publish-heartbeat.sh` — publishes `hang_count` to MQTT
