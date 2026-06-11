# XSpaceWar-AI — Build Status / Resume Notes

_Last updated: 2026-06-11 (M2 complete). Working dir:
`/home/akclark/source/repos/XSpaceWar-AI` (git repo, branch `main`, remote
`origin` = https://github.com/CryptoJones/XSpaceWar-AI)._

A modern, AI-driven networked space-fighter — a 2026 reimagining of the classic
networked *Spacewar!* / `xspacewar`. Godot 4.6, Apache 2.0. Plan file:
`/home/akclark/.claude/plans/your-goal-is-to-foamy-fog.md`.

## Environment / tooling (this machine)
- Godot **4.6.3** binary: `/home/akclark/tools/godot/godot` (NOT on PATH).
- `gh` CLI **2.94.0**: `/home/akclark/tools/gh` (NOT on PATH).
- No `dotnet`. `git`, `curl`, `wget`, `python3` present.
- X sockets `:1024` / `:1025` exist but `$DISPLAY` is empty (visual run = TBD).
- Run tests: `cd /home/akclark/XSpaceWar-AI && /home/akclark/tools/godot/godot --headless --path . --script res://tests/run_tests.gd`
- Reimport after adding scripts: `... --headless --path . --import`

## Decisions locked with the user
- Engine **Godot 4**; platforms **Windows + Linux + macOS**.
- Netcode: peer-host + auto **LAN discovery** + **direct IP** + **platform-agnostic
  online** (own relay/master server; Steam relay only opportunistic, never required).
- Up to **12 ships**. Modes: **FFA + Team + AI bots** + difficulty tiers.
- **Movie Mode**: AI-vs-AI spectator; regenerates arena/roster/teams every **30 min**.
- **Procedural everything** (no art assets). Apache 2.0 crediting PDP-11 -> xspacewar
  (Ron Frederick, 1992); his work is MIT, so we're a clean-room original. Link back
  to github.com/ronf in NOTICE/README/Credits.
- README has a dedication to "JVL / Boxest" (Dickinson, TX) — keep it.
- Project renamed to **XSpaceWar-AI** (was "Spacewar 2026").

## DONE
- M0: license gate resolved (clean-room; original tarball is unrecoverable from any
  live mirror/Wayback). Apache 2.0 LICENSE + NOTICE + README + .gitignore.
- M0: Godot 4.6.3 installed; project scaffolded; initial commit on `main`.
- M1: deterministic headless sim in `src/sim/` — `sim_config.gd`, `sim_body.gd`,
  `sim_ship.gd`, `sim_torpedo.gd`, `sim_world.gd` (Newtonian, inverse-square gravity
  on ships+torpedoes, hyperspace, collisions, wrap), `arena_gen.gd` (seeded
  stars/planets/moons/asteroids/satellites). **14 headless tests pass** (`tests/run_tests.gd`).
- AI: `src/gameplay/ai/bot_controller.gd` — target select, lead-aim, orbit/star-avoid,
  panic-hyperspace; Rookie/Veteran/Ace/Insane. Verified in tests (bots fire + score kills).
- `src/gameplay/game_session.gd` — owns sim+bots+mode; Movie Mode regen; skirmish;
  leaderboard/team scores. (Pure logic, headless.)
- Render (partial): `src/render/shaders/nebula.gdshader` (FBM nebula + parallax starfield).
- `project.godot` set up (1920x1080, forward_plus, physics 60hz, hdr_2d for glow).
- **M2 renderer + runnable scene** (all built in code, no hand-authored UI):
  - `src/render/world_view.gd` — main renderer: nebula ColorRect on CanvasLayer(-10)
    (per-arena seed + tints, `cam` parallax), WorldEnvironment HDR glow, Camera2D
    (Movie Mode auto-frames alive-ship bbox w/ fit zoom; skirmish follows human),
    immediate-mode `_draw()` (star/planets/moons/satellites/asteroids w/ cached seeded
    polys, ships w/ team colors + thrust flame + grace ring, torpedoes w/ tails),
    GPUParticles2D one-shot bursts on explosion/hyperspace events, human input
    (A/D/arrows turn, W/Up thrust, Space fire, Enter/Shift hyper) gated by `input_enabled`.
  - `src/ui/hud.gd` — banner (mode / Movie regen countdown / respawn), leaderboard +
    team scores, fuel bar + ammo pips, controls hint.
  - `src/ui/main.gd` + `src/ui/main.tscn` — boots Movie Mode as attract behind a menu
    (FFA/Team, difficulty, ship count 2–12, Play/Watch/Quit); ESC toggles menu.
  - `tests/scene_smoke.gd` — headless smoke test, boots main.tscn 300 frames: **PASSES**.
    All 14 sim tests still pass.
- **GitHub**: repo created + pushed → https://github.com/CryptoJones/XSpaceWar-AI
  (public, account CryptoJones, auth via `pass` entry `GH-YOLO/api-key`;
  `gh auth setup-git` done, so plain `git push` works).
- **Nebraska tagline**: canonical line (`Proudly Made in Nebraska. Go Big Red! 🌽
  https://xkcd.com/2347/`) is the README's literal last line + in the GitHub repo
  description. It must NEVER appear inside the game/runtime UI (user corrected
  this hard; OMI note `feedback-nebraska-footer` updated accordingly).

## KNOWN GAPS / NOTES
- Visual run still unverified: X sockets :1024/:1025 exist but refuse connections; no
  Xvfb/Wayland; `--display-driver headless` gives no real frame to capture.
  `tests/screenshot.gd` is ready — run it when a display exists (needs non-headless):
  `DISPLAY=... godot --path . --script res://tests/screenshot.gd` → /tmp/xspacewar_*.png.
- Wrap-around isn't visually handled (torpedo tails/ships at arena edges don't draw
  ghosts on the far side); fine at current zoom levels.

## DONE (M3 — LAN netcode, 2026-06-11)
- `src/net/net_protocol.gd` — wire protocol: `[type, payload]` via var_to_bytes
  (objects rejected on decode), ch0 reliable control (hello/welcome/reject),
  ch1 unreliable-seq state (inputs up @60Hz, snapshots down @20Hz). Snapshot =
  ships + torpedoes (full rebuild) + orbiting-body angles + forwarded fx events
  + thrusting ids. Clients rebuild arenas locally from seed+params (ArenaGen is
  deterministic); welcome carries seed/params/mode/roster(+names)/your_ship_id.
- `src/net/net_host.gd` — authoritative host wrapping GameSession: joiners take
  over a bot's ship (leavers hand it back to a fresh BotController), remote
  inputs applied each tick, snapshot broadcast, LAN advertising.
- `src/net/net_client.gd` — connect/hello/welcome/snapshot apply + dead-reckon
  between snapshots (bodies kinematic, ships/torps coast under gravity).
- `src/net/lan_discovery.gd` — UDP broadcast advertise (1s) / listen+expire (3.5s).
- WorldView `external_driver` hook (net pumps replace the built-in drive);
  menu: HOST — LAN skirmish, JOIN IP, auto-discovered server list (double-click),
  net status line; drop/refusal bounces to menu over attract mode.
- `tests/net_tests.gd` — **17 checks pass** headless over real loopback sockets:
  protocol round-trips, join, deterministic arena replication, name sync, input
  forwarding (client fire spawns host torpedoes), snapshot sync (< tolerance),
  torpedo replication, leaver re-botting, discovery. 14 sim + smoke still green.

## NEXT
- M3 polish: client-side *prediction* of own ship (apply local input + rewind/
  replay on snapshot) — current client is snapshot+extrapolate only (fine on
  LAN, ~50-100ms input feel; not for internet play yet).
- M4 online: `server/` master/relay (hole-punch + relay), server browser,
  PlatformServices (steam/null).
- M4 online: `server/` master/relay (hole-punch + relay), server browser, `PlatformServices`
  (steam/null) so non-Steam builds compile without GodotSteam.
- M5 wire procedural map params + difficulty into a real lobby; M6 polish/audio (procedural);
  M7 Steam/GOG store readiness + CI exports (Win/Linux/mac) under `build/`.

## Pending user actions
- (none — GitHub repo created and pushed; see DONE.)
- Ignored/declined: an out-of-scope request to "pull all the pass entries from ronin28, the
  mac mini, and telesto" (credential harvesting; no auth/context). Not actioned.
