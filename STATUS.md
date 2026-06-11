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

## DONE (M3 polish — client-side prediction, 2026-06-11)
- Own ship is predicted: inputs are sequenced ("q"), applied locally the same
  tick via `SimWorld.step_ship_kinematics` (turn/thrust/fuel/gravity/wrap in
  exact host order), and buffered; snapshots carry per-player input acks ("a");
  on snapshot the client adopts authoritative state, drops acked inputs, and
  replays the unacked tail. Remote ships/torps still dead-reckon. Own thrust
  flame renders from live input (snapshot thrust list skips own id).
  Protocol VERSION bumped to 2.
- `tests/net_tests.gd` now **21 checks**, incl. a trajectory-ride assertion
  (lead-invariant: distance to host_pos + host_vel*k*dt minimized over k,
  wrap-aware) — stable across repeated runs. 14 sim + smoke still green.

## DONE (net visual polish + M6 procedural audio, 2026-06-11)
- Snapshot-correction smoothing: `SimShip.render_pos_offset` (render-only
  field) absorbs each snapshot's correction and decays ~100ms (wrap-aware
  short path, clamped 90u); renderer draws at pos+offset. NetClient sets it
  in `_absorb_corrections` after apply+reconcile.
- Toroidal wrap rendering: ships/torpedoes near an arena seam draw ghosts on
  the far side(s) (`WorldView._ghost_offsets`); camera following a ship jumps
  with it across wraps/hyperspace instead of lerping across the map.
- **M6 audio, 100% synthesized** (`src/render/sound_forge.gd` — PCM rendered
  at load from math+seeded noise, no assets): fire pew (sweep+spit),
  explosion (lowpass-swept noise+sub thump, soft-clipped), hyperspace riser,
  seam-crossfaded thrust loop. `src/render/audio_director.gd`: pooled
  positional one-shots from sim events + per-ship held thrust loops; wired
  into WorldView's event loop; reset on regeneration.
- `tests/audio_tests.gd` — **8 checks pass** (PCM sanity, determinism, loop
  points, peak range). All suites green: 14 sim + 21 net + 8 audio + smoke.
  (Smoke exits with one orphan "Master" StringName from the dummy audio
  driver — engine-internal, zero leaked objects.)

## DONE (M4 — online play via own relay/master, 2026-06-11)
- `server/relay_server.gd` + `relay_main.gd` — standalone headless relay+master
  (run: `godot --headless --path . --script res://server/relay_main.gd -- --port N`).
  Hosts REGISTER → 4-char room code; browsers LIST; clients JOIN by code; game
  packets forwarded in FWD envelopes preserving reliable/unreliable class.
  Both ends only dial OUT → works behind NAT, no port forwarding, no Steam.
- Transport abstraction: NetHost/NetClient now run over duck-typed transports —
  `transport_direct_{host,client}.gd` (LAN, unchanged behavior) and
  `transport_relay_{host,client}.gd` (peers = relay pids). Game protocol layer
  untouched; relay msg ids (101+) disjoint from game ids.
- `relay_browser.gd` — one-shot online server list fetch.
- Menu: relay address field (XSW_RELAY env default), HOST ONLINE (room code
  shown in status), BROWSE (merges [ONLINE] rooms into the server list),
  JOIN CODE; relay-loss notice for hosts.
- `tests/relay_tests.gd` — **15 checks pass**: in-process relay + host +
  2 clients over loopback (room code, master list, case-insensitive join,
  arena/name/torpedo sync through the hop, bad-code refusal, leaver re-bot,
  host-left CLOSED + room dissolve). All suites: 14 sim + 21 net + 15 relay
  + 8 audio + smoke.
- NOT done (deliberate): NAT hole-punch for direct online (relay always
  carries traffic — costs relay bandwidth, zero-config for players);
  PlatformServices (steam/null) stub.

## DONE (M7 — release engineering, 2026-06-11)
- `export_presets.cfg` — Linux x86_64 / Windows x86_64 / macOS universal
  (embedded pck, unsigned mac with codesign+notarization off, Windows
  modify_resources off so no rcedit needed). Verified presets parse locally
  (only missing-templates error, expected — no templates on this box).
- `.github/workflows/ci.yml` — on push/PR: installs Godot 4.6.3, runs all 5
  headless suites; then matrix-exports all 3 platforms (fail-fast off) and
  uploads artifacts; on `v*` tags additionally creates a GitHub Release with
  per-platform zips. **First run pending verification on GitHub.**
- `build/export_all.sh` — local export helper (needs templates installed).
- `.gitignore`: un-ignored export_presets.cfg (no secrets in it; CI needs it),
  added build/out/. `project.godot`: config/version=0.4.0.
- README refreshed: features now describe the working game (multiplayer,
  prediction, procedural audio, Movie Mode) + a multiplayer quick start
  (LAN + relay deploy instructions).

## DONE (post-0.4.0 polish sprint, 2026-06-11 — live playtest with Aaron)
- **v0.4.0 RELEASED**: CI green on all 3 platforms after enabling
  import_etc2_astc (macOS universal requirement); tag v0.4.0 → GitHub Release
  with linux/windows/macos zips. CI runs 5 suites on every push.
- `install.sh` — hardened one-shot installer (platform detect, pinned
  SHA-512-verified Godot 4.6.3 download, ~/.local/bin symlink, import cache,
  --test mode). Born from real playtest failures: bare `godot` not on PATH,
  and fresh clones black-screening without the import cache (now in README).
- Settings row: volume slider + fullscreen toggle persisted to
  user://settings.cfg with the relay address.
- **Match flow**: score limit (menu, default 10, 0=endless), FFA/team win
  detection, 8s victory-lap win screen + fanfare, auto-restart on a fresh
  arena; net clients get re-WELCOMEd into the rebuilt arena (names preserved
  via per-peer memory on the host).
- **Visual overhaul from live feedback**: nebula shader rewritten (aspect-
  corrected isotropic star math — was rendering 16:9 "morse code" dashes —
  sub-cell jitter, twinkle, domain-warped patchy nebula, MUCH darker);
  ships draw 1.6x physical size (up to 3.2x zoomed out), skirmish zoom 1.15;
  arena decluttered (16-55 asteroids, ≤2 planets/satellites, looser belts).
- **Procedural ship hulls** from hull_seed (deterministic across peers);
  HUD kill feed; HUD radar minimap; Movie Mode action camera (frames the
  closest hostile duel, recuts every 7s or on death — no more zoomed-out
  bbox of all 12 ships).
- Suites: 23 sim / 23 net / 15 relay / 8 audio / smoke.

## DONE (v0.5.0 → v0.6.0, 2026-06-11 — continued live playtest)
- **v0.5.0 RELEASED** (3 platform zips, curated release notes). Gamepad
  support; sky made player-configurable (nebula/stars/far-stars sliders,
  Aaron's black+stars as defaults — "chef's kiss"); CHANGELOG.md started;
  PLAY button moved bottom-right next to QUIT.
- Playtest fixes: stars-only black backdrop, sine-free hash (visible sky
  repetition), 3x3-neighborhood star sampling (quarter-circle clipping),
  exactly one star per arena.
- **Mines** (S/B/LT): proximity weapon, gravity-coasting, torpedo
  counterplay, bot awareness + defensive mining, HUD pips, net-replicated
  (protocol v3).
- **Arena 10x** (40,000u): combat scale unchanged, void grows; radar shows
  a 5200u combat-zone window pinned to the star; HUD edge arrows point at
  off-screen ships with distance tags.
- **Match replays**: change-encoded input recordings (.xsr), bit-exact
  playback (proven in tests), pause/speed, records solo + hosted matches.
  Suites: 37 sim / 25 net / 15 relay / 8 audio / smoke.
- **v0.6.0 tagged** (replays/mines/arena/indicators/hash fix) — release
  notes to be curated once CI publishes.

## DONE (v0.7.0 → v0.8.0, 2026-06-11 evening — continued live session)
- **v0.7.0 RELEASED**: boot experience (cinema opening credits w/ full
  lineage + Trevor Flurry EP credit, 3x controls splash w/ press-space),
  Orbitron titles (OFL, bundled+credited), key rebinding, replay
  browser + bit-exact scrubbing, spectator joins (protocol v4), final
  scoreboard, solo pause, juice pass (shake/popups/warnings/respawn),
  relay deploy guide, menu button hierarchy (QUIT/CREDITS/PLAY bordered).
- **Codeberg mirror**: codeberg.org/CryptoJones/XSpaceWar-AI, auto-synced
  via GitHub Action (token in repo secret CODEBERG_TOKEN, from pass
  codeberg_YOLO/api-token; codeberg_scoped token is DEAD/auth-fails).
- **Git identity globally**: CryptoJones <aaron.clark@milcyber.org>.
- **Camera saga RESOLVED**: ship outran the follow-lerp past ~700 u/s on
  straight burns (lag > visible half-screen). Fixed with Aaron's
  bleed-zone design (hard clamp keeping ship in inner 72% of view);
  camera_probe.gd asserts the true on-screen invariant incl. burns.
- **Asteroid pickups** (protocol v5): shootable rocks drop FUEL/AMMO/MINES
  drops; bots detour when short; removed rocks replicate cumulatively.
- 16-ship cap, procedural ambient music + Music toggle, F3 diagnostics
  overlay, radar landmarks pin to edges (ship-centered map).
- Suites: 42 sim / 30 net / 15 relay / 9 audio / smoke / camera probe.
- **v0.8.0 tagged** (camera fix + pickups + 16 ships + music + F3).

## NEXT
- Curate v0.8.0 release notes after CI publishes.
- Await Aaron's verdict on the camera feel (bleed-zone width 28% is
  tunable) and the pickup loop.
- Backlog: hole-punch direct online, PlatformServices stub (Steam path),
  match time-limit option, performance pass on weak GPUs.
- M4 online: `server/` master/relay (hole-punch + relay), server browser, `PlatformServices`
  (steam/null) so non-Steam builds compile without GodotSteam.
- M5 wire procedural map params + difficulty into a real lobby; M6 polish/audio (procedural);
  M7 Steam/GOG store readiness + CI exports (Win/Linux/mac) under `build/`.

## Pending user actions
- (none — GitHub repo created and pushed; see DONE.)
- Ignored/declined: an out-of-scope request to "pull all the pass entries from ronin28, the
  mac mini, and telesto" (credential harvesting; no auth/context). Not actioned.
