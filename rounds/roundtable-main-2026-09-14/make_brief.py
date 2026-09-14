#!/usr/bin/env python3
import pathlib

files = [
    ('src/sim/sim_world.gd', 'Simulation Core (SimWorld)'),
    ('src/sim/torus.gd', 'Toroidal Arena Math (Torus)'),
    ('src/sim/systems/collision_system.gd', 'Collision System & Swept Physics'),
    ('src/sim/systems/spawn_system.gd', 'Spawn System & Grace Geometry'),
    ('src/net/net_protocol.gd', 'Net Protocol & Safe Unpack'),
    ('src/net/net_host.gd', 'Host-Authoritative Network Host'),
    ('src/gameplay/aim_analyzer.gd', 'Aim Anomaly Heuristics'),
    ('src/gameplay/ai/bot_behaviors.gd', 'AI Bot Behaviors & Difficulty'),
    ('server/dedicated_main.gd', 'Dedicated Server & Moderation Console'),
]

header = """# Brief: Code Review of XSpaceWar-AI (main branch)

You are one lane of an independent FlatlineRoundtable review panel.
Answer only from what is provided below; do not attempt to read the filesystem or shell out.
Be concise, direct, and adversarial. Lead with concrete findings. Say "unsure" or "no defect found" rather than speculating.

## Context & Architecture

- **Project**: XSpaceWar-AI (https://github.com/CryptoJones/XSpaceWar-AI)
- **Branch**: main (commit 20c5697, release v5.0.0+)
- **Engine**: Godot 4.6.3 (GDScript), headless-capable, running at fixed 60Hz physics / 20Hz net snapshots.
- **Domain**: Newtonian space-fighter combat (Spacewar! / xspacewar clean-room reimagining).
- **Core Architecture**:
  1. **Deterministic Sim**: Pure headless `SimWorld` in `src/sim/` with fixed pipeline order: Gravity -> Spawn -> Torpedo/Mine -> Ship Kinematics -> Pickups -> Swept Collisions -> Wrap with Slingshot. Arena geometry is toroidal (`Torus`). Deterministic RNG (`SimWorld.rng`).
  2. **Host-Authoritative Netcode**: Clients send sequenced inputs (`q`), host processes and broadcasts snapshots (`a`). Safe deserialization via `bytes_to_var` (objects rejected). Strict DoS bounds: `MAX_CLIENT_PACKET = 4096`, `MAX_PEERS_PER_IP = 4`, `MAX_PACKETS_PER_PUMP_PER_PEER = 8`, `MAX_INPUT_SEQ_GAP = 1024`.
  3. **Multiplayer & Moderation**: In-game `PlayersPanel`, dedicated console `/kick`, `/ban`, `/unban`, persistent `--banfile`. Heuristic `AimAnalyzer` for cheat monitoring (surface warnings only; never auto-bans).
  4. **AI & Difficulty**: `BotController` + `BotBehaviors` with skill tiers (Rookie, Veteran, Ace, Insane). Enemy ship visual size scales inversely with difficulty (Rookies fly larger, easier targets).
  5. **Dedicated Server**: `server/dedicated_main.gd` headless server for Linux/macOS/Windows VPS.

## Deliberate Decisions (Do NOT litigate these)
- Engine is Godot 4 / GDScript. Do not propose rewriting in C++, Rust, or C#.
- Visuals and audio are 100% procedural (no sprite/audio asset dependencies).
- Anticheat relies on host-authoritative simulation + aim anomaly heuristics + moderation tooling. Kernel anticheat is an explicit non-goal.
- Relay server provides zero-config NAT traversal; direct online hole-punching is not required.

## Review Questions

Evaluate the provided codebase against these 5 concrete, falsifiable questions:

1. **Sim Determinism & Arithmetic Edge Cases**:
   - In `sim_world.gd`, `torus.gd`, `collision_system.gd`, or `spawn_system.gd`, are there division-by-zero vulnerabilities (e.g. `r == 0` or near-zero distance to star/planets/mines), NaN/Inf propagation, or unseeded random calls?
   - Can toroidal wrapping or swept collision tunneling cause entities to escape the arena or create infinite loops?

2. **Netcode & Packet Security**:
   - In `net_protocol.gd` and `net_host.gd`, can a malicious client crash the host, cause memory leaks, trigger unbounded dictionary growth, spoof another player's ship/slot, or bypass packet/rate limits?
   - Is `NetHost`'s input sequence gap guard (`MAX_INPUT_SEQ_GAP = 1024`) vulnerable to wrap-around or sequence exhaustion over long-running matches?

3. **Bot AI & Behavior Trees**:
   - In `bot_behaviors.gd`, are there failure modes where bots freeze, fail to acquire targets, loop infinitely, crash on null/dead targets, or miscalculate toroidal lead aim across the arena wrap?
   - Does difficulty scaling introduce any edge-case game breaks?

4. **Dedicated Server, Moderation & Persistence**:
   - In `dedicated_main.gd` and `aim_analyzer.gd`, are there concurrency/lifecycle bugs, file corruption risks with `--banfile` under concurrent or interrupted writes, command injection in the moderation console, or memory leaks over multi-hour matches?

5. **Dead Code, Missing Guards & Fragile Constructs**:
   - What error conditions or state transitions are unhandled or fragile across these load-bearing files before shipping a major public release?

---
"""

out = [header]
for rel_path, title in files:
    content = pathlib.Path(rel_path).read_text()
    out.append(f"## File: `{rel_path}` — {title}\n\n```gdscript\n{content}\n```\n")

brief_text = "\n".join(out)
dest = pathlib.Path("rounds/roundtable-main-2026-09-14/brief.md")
dest.write_text(brief_text)
print(f"Wrote brief.md: {len(brief_text)} bytes, {len(brief_text.splitlines())} lines")
