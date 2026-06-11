# XSpaceWar-AI Relay / Master Server

The relay is what makes **internet play** work with zero configuration for
players: game hosts register here and get a 4-letter room code, browsers
fetch the room list, and all game traffic is forwarded through this box —
both ends only dial *out*, so nobody port-forwards anything.

One small VPS comfortably serves many simultaneous rooms; traffic per
12-ship room is on the order of tens of KB/s.

## Requirements

- Any Linux box players can reach (a $5 VPS is plenty).
- The Godot 4.6.x binary (standard build) — `install.sh` in the repo root
  fetches a SHA-512-verified copy.
- This repository (the relay runs from the project's scripts).
- **UDP port 24645** open inbound (configurable with `--port`).

## Quick start

```bash
git clone https://github.com/CryptoJones/XSpaceWar-AI.git
cd XSpaceWar-AI
./install.sh
godot --headless --path . --script res://server/relay_main.gd -- --port 24645
```

You should see:

```
XSpaceWar relay/master listening on UDP 24645
```

Open the firewall:

```bash
sudo ufw allow 24645/udp        # Debian/Ubuntu with ufw
# or: firewall-cmd --add-port=24645/udp --permanent && firewall-cmd --reload
```

## Players point at it

In the game menu, enter `your-server.example.com:24645` in the relay field
(or set the `XSW_RELAY` environment variable to skip typing it). Then:

- **HOST ONLINE** registers a room and shows its 4-letter code,
- **BROWSE** lists every open room on this relay,
- **JOIN CODE** joins by code — *Spectate* joins without taking a ship.

## Run it as a service (systemd)

`/etc/systemd/system/xspacewar-relay.service`:

```ini
[Unit]
Description=XSpaceWar-AI relay/master server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=xspacewar
WorkingDirectory=/opt/XSpaceWar-AI
ExecStart=/opt/godot/godot --headless --path /opt/XSpaceWar-AI --script res://server/relay_main.gd -- --port 24645
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo useradd -r -d /opt/XSpaceWar-AI -s /usr/sbin/nologin xspacewar
sudo systemctl daemon-reload
sudo systemctl enable --now xspacewar-relay
journalctl -u xspacewar-relay -f     # watch it
```

## Notes

- The relay holds no game state beyond room membership — restarting it
  drops active rooms (players just re-host), nothing else.
- Rooms vanish automatically when their host disconnects.
- Protocol versions must match between game clients and the relay's repo
  checkout; update the relay when you ship breaking protocol changes
  (see `NetProtocol.VERSION`).

Proudly Made in Nebraska. Go Big Red! 🌽 https://xkcd.com/2347/
