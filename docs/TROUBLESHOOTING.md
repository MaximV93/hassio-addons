# Troubleshooting `haos-sbfspot` (powerslider fork)

Quick reference when the addon stops producing data. Checks are ordered from cheapest to most invasive.

## 1. Is the addon running?

**Symptom**: `sensor.haos_sbfspot_powerslider_sbfspot_cron_heartbeat` is stale (last update > 2 min).

**Checks**:
```bash
# Via HA CLI (or Supervisor API):
ha apps info haos-sbfspot   # check "state: started"
```

Addon log via supervisor:
- Settings → Add-ons → HAOS-SBFspot (powerslider) → Log tab
- Last 100 lines only. For more history, look at `/data/logs/sbfspot-YYYY-MM-DD.log` via Samba share.

If state is `stopped` or `error`: restart via UI. If it crashes on start, check `config.yaml` options for syntax errors.

## 2. Is cron firing?

**Symptom**: Heartbeat fresh, but `sensor.haos_sbfspot_powerslider_sbfspot_last_run_status` is `missing` or stuck.

`publish-heartbeat.sh` fires every minute independently of SBFspot. If `cron_heartbeat` is fresh, cron works.

If heartbeat stale too → crond died. Restart addon.

## 3. Is SBFspot reaching the inverter?

**Symptom**: `last_run_status = failed-N` for some N. `hang_count` increasing.

**Most common causes**:

| Failure mode | Symptom | Fix |
|---|---|---|
| Wrong Bluetooth password | `CRITICAL: Logon failed. Check 'USER' Password` | Update `Password` option. Default is `0000`; installers often change it. |
| BT dongle not attached | `bthConnect() returned -1` after all retries | Check USB dongle passthrough at hypervisor. `host_network: true` in config (don't change). |
| Inverter asleep | `Serial Nr: xxxx` but no data fields | Normal at night. SBFspot's `SunRSOffset` option (default 900 s) gates this. |
| BT signal too weak | Frequent hangs (`hang_count` keeps rising) | Move repeater closer, or lower poll rate, or raise `SBFspotTimeoutSec` |
| MIS mode without matching NetID | Only primary inverter shows up | All inverters + repeater must share NetID. Set via inverter display or Sunny Explorer. |

Full-text of persistent logs at `/data/logs/sbfspot-YYYY-MM-DD.log`:

```bash
# Inspect last 24 h hang events:
grep 'HANG' /data/logs/sbfspot-$(date +%Y-%m-%d).log
```

## 4. Is data reaching Home Assistant?

**Symptom**: SBFspot log shows `MQTT: Publishing` but `sensor.haos_sbfspot_sma_ac_power` stays at 0 / stale.

**Checks**:

- **MQTT broker reachable**: `ha apps info core_mosquitto` → state started.
- **Credentials correct**: `MQTT_User` / `MQTT_Pass` in addon options match a login in Mosquitto broker's options. Default login lives in `core_mosquitto` addon config.
- **Discovery published**: subscribe to `homeassistant/sensor/+/config` (MQTT Explorer or `mosquitto_sub -t 'homeassistant/sensor/+/config' -v`). You should see configs for your inverter serials.
- **Sensor in registry**: HA → Developer Tools → States → search for `haos_sbfspot`.

## 5. Empty / weird values

| Symptom | Likely cause |
|---|---|
| `PACTot = 0` at midday | Inverter isn't producing (weather, grid fault, inverter off). |
| `ETotal` drops suddenly | Counter rollover or sensor reset. Check `state_class: total_increasing` logic in HA. |
| `InvTemperature = 0` at night | Inverter is asleep, no sensor data. Normal. |
| Fresh data but dashboard empty | Entity name changed (HA prefixes with device name). Re-check entity IDs. See ADR-003. |

## 6. Upgrade broke something

Recent versions:
- `2026.4.17.13` removed the (non-working) migrate() trick from 02-publish-heartbeat-discovery.sh
- `2026.4.17.12` added `object_id` to discovery configs (new installs only)
- `2026.4.17.8` introduced heartbeat sensors + run-sbfspot.sh wrapper
- `2026.4.17.6` tried `host_network: false`, broke BT. **Do not downgrade to 6/7/8 from 9+** unless you want to test that regression.

Rollback: addon UI → 3-dot menu → Rebuild → pick previous version from dropdown. Or rebuild from source tag via Supervisor CLI.

### Stuck entity IDs after upgrade

**Symptom**: you upgraded past `2026.4.17.12` but your heartbeat sensors are
still named `sensor.haos_sbfspot_powerslider_sbfspot_*` instead of
`sensor.sbfspot_*`.

**Cause**: HA's entity registry is sticky by `unique_id`. Adding `object_id`
to MQTT discovery only affects brand-new registry entries. Publishing an
empty payload to the discovery topic removes the MQTT binding but leaves
the registry entry intact — so HA re-uses the old entity_id when the new
discovery arrives.

**Fix (UI)**: Settings → Devices & Services → MQTT → sbfspot_addon device
→ click each of the 4 sensors → edit ID → set to the short name.

**Fix (WebSocket, scripted)**: call `config/entity_registry/update` with
`entity_id` (old) and `new_entity_id` (new). See the rename helper at
`haos-sbfspot/tools/rename_legacy_entities.py`.

## 7. Data comes in, but hangs are frequent

`hang_count` rising faster than 1/hour suggests systemic BT issue.

1. Place BT repeater physically closer to the farthest inverter
2. Raise `SBFspotTimeoutSec` if your runs legitimately take >50 s (check `last_run_duration` for successful-run baseline)
3. Lower `BTConnectRetries` (addon option) from upstream's default 10 → 3; fewer retries = faster failure
4. If one inverter is consistently the culprit (check `/data/logs/` for serial numbers in hang events), consider running two addon instances: one per inverter on separate NetID

## 8. "The fork is broken, I want to go back to upstream habuild"

```
Supervisor → Add-ons → HAOS-SBFspot (powerslider) → Uninstall
Supervisor → Add-on store → 3-dot → Repositories → add https://github.com/habuild/hassio-addons
Install HAOS-SBFspot (from habuild repo)
```

Your data in MariaDB (`sbfspot` database) stays intact — both addons use the same schema.

MQTT discovery entities from the powerslider fork (`sensor.haos_sbfspot_powerslider_*`) become orphaned; HA removes them after 3 hours without updates.

## Reporting issues

- **Fork-specific**: https://github.com/MaximV93/hassio-addons/issues
- **Upstream SBFspot**: https://github.com/SBFspot/SBFspot/issues (C++ core, common to all forks)
- **Upstream wrapper**: https://github.com/habuild/hassio-addons/issues (things we didn't change)
