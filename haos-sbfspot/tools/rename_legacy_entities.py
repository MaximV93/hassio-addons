#!/usr/bin/env python3
"""Rename legacy long-named SBFspot heartbeat entities to short names.

Needed when upgrading from <= 2026.4.17.11 to 2026.4.17.12+: HA's entity
registry is sticky by unique_id, so adding object_id to MQTT discovery alone
does not rename existing entities. This script calls the WebSocket
config/entity_registry/update endpoint to do the rename in-place.

Usage:
    HA_TOKEN=xxx HA_URL=ws://127.0.0.1:8123/api/websocket \
        python3 rename_legacy_entities.py

Safe to run multiple times — already-renamed entities will simply error
with "entity not found" (no-op).
"""
import asyncio
import json
import os
import sys

try:
    import websockets
except ImportError:
    print("pip3 install websockets", file=sys.stderr)
    sys.exit(1)

TOKEN = os.environ.get("HA_TOKEN")
WS_URL = os.environ.get("HA_URL", "ws://127.0.0.1:8123/api/websocket")

RENAMES = [
    ("sensor.haos_sbfspot_powerslider_sbfspot_cron_heartbeat", "sensor.sbfspot_cron_heartbeat"),
    ("sensor.haos_sbfspot_powerslider_sbfspot_last_run_status", "sensor.sbfspot_last_status"),
    ("sensor.haos_sbfspot_powerslider_sbfspot_hang_count", "sensor.sbfspot_hang_count"),
    ("sensor.haos_sbfspot_powerslider_sbfspot_last_run_duration", "sensor.sbfspot_last_duration"),
]


async def main():
    if not TOKEN:
        print("Set HA_TOKEN (long-lived access token)", file=sys.stderr)
        sys.exit(1)

    async with websockets.connect(WS_URL) as ws:
        hello = json.loads(await ws.recv())
        if hello.get("type") != "auth_required":
            print(f"Unexpected handshake: {hello}", file=sys.stderr)
            sys.exit(1)
        await ws.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        auth = json.loads(await ws.recv())
        if auth.get("type") != "auth_ok":
            print(f"Auth failed: {auth}", file=sys.stderr)
            sys.exit(1)

        mid = 1
        for old, new in RENAMES:
            mid += 1
            await ws.send(json.dumps({
                "id": mid,
                "type": "config/entity_registry/update",
                "entity_id": old,
                "new_entity_id": new,
            }))
            resp = json.loads(await ws.recv())
            ok = resp.get("success")
            err = resp.get("error", {}).get("message", "") if not ok else ""
            status = "OK " if ok else "ERR"
            print(f"{status} {old} -> {new}  {err}")


if __name__ == "__main__":
    asyncio.run(main())
