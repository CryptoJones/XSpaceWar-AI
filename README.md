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

## Features (target)

- Top-down arena dogfights around a gravity well, up to **12 ships**.
- Modern **Newtonian** flight — conserved momentum, inverse-square gravity on
  ships *and* torpedoes, gravity-assist slingshots, hyperspace.
- **Procedurally generated** stars, planets, moons, asteroid fields, nebulae,
  ships, and VFX — every match a new seeded arena.
- **Game modes:** Free-for-all, Team battle, and AI bots (Rookie → Insane).
- **Multiplayer:** peer-host with automatic **LAN discovery**, **direct IP**,
  and platform-agnostic **internet** play via an optional relay/master server.
  (Steam relay used opportunistically when present, never required.)

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

## Building & running

Requires **Godot 4.x** (standard build).

```bash
# Run the game
godot --path .

# Run headless simulation tests
godot --headless --path . --script res://tests/run_tests.gd
```

## Dedication

Thank You to "JVL / Boxest" for all the nights we stayed up playing Ron Fredrick's game
in 90s-era Dickinson, Texas. HTMFPWGCBNOTDOD!

## License

Apache License 2.0 — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

Proudly Made in Nebraska. Go Big Red! 🌽 https://xkcd.com/2347/
