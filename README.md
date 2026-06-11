# XSpaceWar-AI

A modern, AAA-styled networked **space-fighter** with a strong AI focus — a
2026 reimagining of the classic networked *Spacewar!* / `xspacewar`. Bird's-eye
view like the original, but with
**space-accurate Newtonian physics**, **100% procedurally-generated graphics**
(no hand-drawn art assets), and **LAN + internet multiplayer for up to 12
ships**.

Built with **Godot 4** for **Windows, Linux, and macOS**. Licensed under
**Apache 2.0**.

---

## Heritage

XSpaceWar-AI stands on the shoulders of one of gaming's oldest lineages:

- **Spacewar!** — MIT, 1962, on the DEC **PDP-1** (Steve Russell et al.).
- **PDP-11 port** — Bill Seiler & Larry Bryant, 1974. The networked
  space-fighter spirit this project carries forward.
- **xspacewar 1.2** — an **X11/C** version written by **Ron Frederick** in
  **1992**, an early *serverless* networked multiplayer game where peers shared
  state directly (IP unicast/multicast) and each client simulated independently.

This is an **original clean-room implementation** — see [`NOTICE`](NOTICE) for
full attribution. Huge thanks to **Ron Frederick**
([github.com/ronf](https://github.com/ronf) ·
[webrtc-spacewar](https://github.com/ronf/webrtc-spacewar) ·
[timeheart.net/spacewar](https://www.timeheart.net/spacewar)) whose 1992
networked Spacewar is this game's direct ancestor.

## Features

- Top-down arena dogfights around a gravity well, up to **12 ships**.
- Modern **Newtonian** flight — conserved momentum, inverse-square gravity on
  ships *and* torpedoes, gravity-assist slingshots, hyperspace.
- **Procedurally generated everything** — stars, planets, moons, asteroid
  fields, nebulae, ships, VFX, *and audio* (every sound is synthesized from
  math at load) — every match a new seeded arena.
- **Game modes:** Free-for-all, Team battle, AI bots (Rookie → Insane), and
  **Movie Mode** — an all-AI spectator attract that regenerates a fresh
  arena, roster, and teams every 30 minutes.
- **Multiplayer (working today):** host-authoritative netcode with
  client-side prediction + reconciliation, automatic **LAN discovery**,
  **direct IP**, and platform-agnostic **internet play** via this repo's own
  relay/master server — room codes, an online server browser, and no port
  forwarding or platform services required.

## Multiplayer quick start

- **LAN:** one player clicks *HOST — LAN skirmish*; everyone else sees the
  game in the menu's server list (or uses *JOIN IP*).
- **Internet:** run the relay on any mutually reachable box (a $5 VPS works):

  ```bash
  godot --headless --path . --script res://server/relay_main.gd -- --port 24645
  ```

  Players put `that-box:24645` in the relay field (or set `XSW_RELAY`), the
  host clicks *HOST ONLINE* and shares the 4-letter room code, friends use
  *JOIN CODE* or *BROWSE*.

## Project layout

```
src/sim/        Deterministic, render-free game simulation (fixed timestep)
src/net/        Host/join, LAN discovery, matchmaking, platform services
src/gameplay/   Game modes, AI bots, scoring, spawning
src/render/     Procedural shaders, particles, ship/starfield visuals
src/ui/         Menus, server browser, HUD, settings
server/         Standalone relay/master service
tests/          Headless simulation tests
build/          Export presets + CI scripts (Win/Linux/macOS)
```

The simulation in `src/sim/` is **deterministic and headless** (no rendering
deps, fixed timestep) so the authoritative host sim, client-side prediction,
AI, and replay all share one codebase.

## Getting the game

**Prebuilt binaries (no engine needed):** grab the zip for your platform from
the [Releases page](https://github.com/CryptoJones/XSpaceWar-AI/releases).
Every push to `main` also uploads fresh builds as artifacts on the
[Actions tab](https://github.com/CryptoJones/XSpaceWar-AI/actions) (sign-in
required), e.g.:

```bash
gh run download --repo CryptoJones/XSpaceWar-AI -n xspacewar-ai-linux-x86_64
chmod +x xspacewar-ai.x86_64 && ./xspacewar-ai.x86_64
```

## Running from source

The repo ships no engine binary — install **Godot 4.6.x** (standard build,
not .NET) from the
[official releases](https://github.com/godotengine/godot/releases/tag/4.6.3-stable):

```bash
# Linux example
mkdir -p ~/tools/godot && cd ~/tools/godot
curl -LO https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_linux.x86_64.zip
unzip Godot_v4.6.3-stable_linux.x86_64.zip && mv Godot_v4.6.3-stable_linux.x86_64 godot
```

(Windows: `Godot_v4.6.3-stable_win64.exe.zip` · macOS:
`Godot_v4.6.3-stable_macos.universal.zip` — same page.)

```bash
# Run the game
godot --path .

# Run the headless test suites
godot --headless --path . --script res://tests/run_tests.gd     # sim
godot --headless --path . --script res://tests/net_tests.gd     # LAN netcode
godot --headless --path . --script res://tests/relay_tests.gd   # online relay
godot --headless --path . --script res://tests/audio_tests.gd   # synthesis
godot --headless --path . --script res://tests/scene_smoke.gd   # scene boot

# Export release builds locally (needs export templates installed)
build/export_all.sh
```

## Dedication

Thank You to "JVL / Boxest" for all the nights we stayed up playing Ron Fredrick's game
in 90s-era Dickinson, Texas. HTMFPWGCBNOTDOD!

## License

Apache License 2.0 — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

Proudly Made in Nebraska. Go Big Red! 🌽 https://xkcd.com/2347/
