# XSpaceWar-AI — Build Status / Resume Notes

_Last updated: 2026-06-11. Working dir: `/home/akclark/XSpaceWar-AI` (git repo,
branch `main`)._

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
- `project.godot` set up (1920x1080, forward_plus, physics 60hz).

## IN PROGRESS / NEXT (M2 — renderer + runnable scene)
1. `src/render/world_view.gd` (Node2D) — the main renderer. Plan:
   - Background: CanvasLayer(layer<0) + ColorRect(full rect) with `nebula.gdshader`;
     feed `cam` (camera pos) + `seed` uniforms each frame for parallax.
   - WorldEnvironment + Environment **glow** for HDR bloom (enable `rendering/viewport/hdr_2d=true`
     in project.godot; draw ships/torpedoes/star with colors >1.0 to bloom).
   - Camera2D: Movie Mode auto-frames centroid of alive ships (fit zoom); skirmish follows human.
   - `_draw()` immediate mode in world space: star (layered additive circles), planets
     (shaded circle + offset highlight, color from body.seed), moons/satellites (small circles),
     asteroids (irregular polygon from seed), ships (needle/wedge polygon by `angle`,
     team color, flame when thrusting — collect thrust ship ids from `world.events`),
     torpedoes (bright additive dots + short velocity tail), spawn-grace shield ring.
   - VFX: spawn one-shot `GPUParticles2D` explosions on `{"type":"explosion"}` events
     (ParticleProcessMaterial built in code; free via SceneTreeTimer).
   - Drive sim from `_physics_process(dt)`: read human input (skirmish) onto human ship,
     call `session.update(dt)`, process events, update camera, `queue_redraw()`.
2. `src/ui/hud.gd` + a CanvasLayer HUD: scoreboard/leaderboard, Movie Mode banner +
   "next regen in mm:ss", fuel/ammo for human, controls hint.
3. `src/ui/main.gd` + **`src/ui/main.tscn`** (referenced by project.godot `run/main_scene`,
   does not exist yet — that's why import logs an error). Minimal root Node2D w/ main.gd that
   boots **Movie Mode** as attract, plus a simple menu overlay (Movie Mode / Skirmish vs AI /
   Quit) and difficulty+ship-count selectors. Build most UI in code to avoid hand-authoring .tscn.
4. Human controls for skirmish: read keys via `Input.is_physical_key_pressed` (turn=A/D or
   arrows, thrust=W/Up, fire=Space, hyper=Enter/Shift).
5. Try a real visual run (set DISPLAY=:1024) + screenshot to verify; else verify headless that
   the scene loads and `_physics_process` runs without script errors.

## LATER (per plan milestones)
- M3 netcode (host-authoritative ENet + UDP LAN discovery + prediction), `src/net/`.
- M4 online: `server/` master/relay (hole-punch + relay), server browser, `PlatformServices`
  (steam/null) so non-Steam builds compile without GodotSteam.
- M5 wire procedural map params + difficulty into a real lobby; M6 polish/audio (procedural);
  M7 Steam/GOG store readiness + CI exports (Win/Linux/mac) under `build/`.

## Pending user actions
- **GitHub repo**: user chose **Public**. `gh` installed + initial commit done, but user is
  NOT yet authenticated. After `/home/akclark/tools/gh auth login`, run:
  `gh repo create XSpaceWar-AI --public --source . --remote origin --push`
- Ignored/declined: an out-of-scope request to "pull all the pass entries from ronin28, the
  mac mini, and telesto" (credential harvesting; no auth/context). Not actioned.
