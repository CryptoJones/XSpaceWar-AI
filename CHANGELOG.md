# Changelog

All notable changes to **XSpaceWar-AI**.

## [1.0.1] — 2026-06-11

### Fixed
- **The minimap, off-screen arrows, respawn countdown, and final
  scoreboard were invisible in 1.0.0** — a code-structure bug truncated
  the HUD's setup, so they were never created. All restored, and CI now
  fails on any runtime script error so this class of bug can't hide.

### Changed
- Gauges (fuel/ammo/mines) moved top-center under the banner; the
  bottom-right key-hint text removed (the KEYS panel and splash own it).
- Menu subtitle shows the running version.
- Credits roller font sizes reduced by 1 across the board.
- Respawn cooldown is now 6 seconds.

## [1.0.0] — 2026-06-11

**1.0.** The original vision, complete: a modern AI-driven networked
space-fighter with deterministic Newtonian physics, 100% procedural
graphics and audio, LAN + internet multiplayer with prediction, bots with
personalities, bit-exact replays, and a full match system — built in one
continuous live session. From 1.0.0 onward every release ships macOS,
Windows, and Linux packages.

### Added
- **Asteroids hazard slider**: 0 = clean space, 100 = roughly every 3rd
  cell of the combat zone holds a randomized rock (deterministic per seed;
  Movie Mode rolls its own level per arena).
- **Time limit** match option (0–30 min): HUD countdown; the clock expiring
  crowns the current leader (team totals in team mode).
- **M** toggles the minimap (persisted).

### Changed
- The classic minimap is back: fixed star-centered overview in the
  **bottom-left** corner (bars stacked above it); everything outside the
  window — including your own ship — pins to the rim with its bearing.

## [0.8.0] — 2026-06-11

### Added
- **Asteroid busting**: torpedoes shatter asteroids; ~⅓ drop a drifting
  supply pickup — **F**uel cell, **A**mmo crate, or **M**ine rack — that
  coasts under gravity, expires in 20s, and grants cargo on contact. Bots
  detour for supplies they're short on (but never abandon an enemy in
  firing range). Fully replicated online and replay-safe.
- **Up to 16 ships** (was 12) everywhere: skirmish, Movie Mode rosters,
  online rooms.
- **Procedural ambient music** — a 16s evolving space drone, synthesized
  like everything else; Music toggle in settings.
- **F3 diagnostics overlay**: fps, tick, ship/camera state, session role.
- Camera failsafe breadcrumb logging.

### Fixed
- **The ship could outrun its own camera** on long straight burns (follow
  lag grows with speed and beat the visible half-screen past ~700 u/s).
  Fixed with the bleed-zone rule, designed by Aaron: the ship may never
  leave the screen — entering the outer 28% of the view pushes the map
  instead. The regression probe now asserts that exact invariant.
- Radar going empty far from home after the ship-centered change — the
  star (and planets) now pin to the radar's edge so the way home is
  always visible.

## [0.7.0] — 2026-06-11

### Added
- **Boot experience**: flat cinema-scale opening credits (original
  developers first, skippable with SPACE, replayable via the CREDITS
  button), then a controls splash — keyboard + gamepad reference at 3×
  scale with a blinking PRESS SPACE BAR TO CONTINUE.
- **Titles set in Orbitron** (SIL OFL 1.1, bundled with license + NOTICE
  attribution).
- **Key rebinding** (KEYS… in settings): rebind the six flight actions,
  persisted per player; the splash reference shows live binds.
- **Replay browser**: list every recording with duration and pilot count;
  watch, delete. **Replay scrubbing**: ◄/► seek ±10s — backward seeks
  re-simulate deterministically and stay bit-exact.
- **Spectator joins**: tick *Spectate* to watch an online match without
  taking a ship; the action camera directs.
- **End-of-match scoreboard**: final standings (and team totals) under the
  winner banner.
- **Game-feel pass**: screen shake on nearby blasts, floating "+1" kill
  popups, low-fuel/no-ammo warning flashes, big respawn countdown.
- **Relay deployment guide** (`server/README.md`): firewall, systemd unit,
  player setup.
- **Codeberg mirror**, auto-synced on every push.

### Changed
- Opening the menu pauses SOLO skirmishes (the Movie Mode attract keeps
  playing behind it).
- Menu bottom row: QUIT / CREDITS / PLAY with bordered buttons — PLAY
  thickest and brightest.

### Fixed
- Title font silently falling back when the import cache was stale, and
  the bold weight variation using the wrong dictionary key form.

## [0.6.0] — 2026-06-11

### Added
- **Match replays**: enable *Record matches* and every match saves a tiny
  input recording (`user://replays/*.xsr` — kilobytes per minute). Playback
  is **bit-exact** thanks to the deterministic sim, directed by the Movie
  Mode action camera, with pause (P) and 1×/2×/4× speed (F). Records solo
  skirmishes and matches you host online.
- **Mines**: drop one behind you (S/Down, pad B/LT) — it keeps most of your
  velocity and coasts under gravity, so minefields drift and orbit. Arms
  after 0.7s; your own mine never trips on you (the blast is another story).
  **Torpedoes detonate them** — shoot your way through. Bots dodge armed
  mines, and brawler/opportunist personalities mine their pursuers. HUD pips
  show your supply of three.
- **Off-screen ship indicators**: edge arrows point at every off-screen
  ship — enemies bright with a live distance tag, teammates dimmed.

### Changed
- **The arena is 10× larger** (40,000 units). Combat keeps its scale around
  the star — what grew is the void. The radar now maps a fixed combat-zone
  window centered on the star, pinning out-of-window ships to its edge.
- Menu: PLAY moved to the bottom row, right of QUIT.

### Fixed
- Visible repeating patterns in the starfield — the sine-based hash went
  periodic at large coordinates; replaced with a sine-free hash.

## [0.5.0] — 2026-06-11

### Added
- **Match flow**: score limit (default 10, 0 = endless), winner banner +
  synthesized fanfare, 8-second victory lap, then auto-restart on a fresh
  arena — works solo and networked (clients are re-welcomed into the rebuilt
  arena with names preserved).
- **Bot personalities**, seeded per hull: Brawler, Sniper, Slingshotter
  (bends its attack runs around the star for gravity assists), and
  Opportunist. Veteran+ bots predictively dodge lethal bodies; rookies still
  fly into rocks.
- **Procedural pilot callsigns** (GRIMJET, VECTORFANG, …) on the
  scoreboard, kill feed, and win banner — synced to net clients.
- **Procedural ship hulls**: every silhouette is generated from its hull
  seed, identical on every peer; exhaust flames anchor to each stern.
- **HUD**: kill feed and a radar minimap.
- **Movie Mode action camera**: frames the closest duel and recuts every few
  seconds or when a combatant dies.
- **Gamepad support**: analog stick turn, A/RT thrust, X/RB fire, Y/LB
  hyperspace, START for the menu.
- **Settings** (persisted per player): volume, fullscreen, and sky
  preferences — nebula intensity, star brightness, far-star layer.
- **install.sh**: hardened one-shot installer — platform detect, SHA-512
  verified Godot download, PATH setup, project import cache, `--test` mode.

### Changed
- Backdrop defaults to **pure black with two parallax star layers**; the
  nebula is opt-in via Settings.
- Ships render 1.6–3.2× their physical size for readability; the skirmish
  camera sits closer; torpedoes scale to match.
- Arenas decluttered: **exactly one star per map**, fewer asteroids, planets,
  and satellites, looser belt scatter.

### Fixed
- Background stars rendered as horizontal 16:9 dashes ("morse code") — star
  math now runs in aspect-corrected isotropic space.
- Stars clipped into quarter circles at star-grid tile edges — each pixel now
  samples its full 3×3 cell neighborhood.
- Fresh clones black-screened on first launch without the import cache (now
  handled by install.sh and documented).
- HDR glow misbehaving on non-Forward+ renderers — skipped cleanly, the game
  just loses bloom.

## [0.4.0] — 2026-06-11

First playable release.

- Deterministic Newtonian simulation: inverse-square gravity on ships *and*
  torpedoes, hyperspace, toroidal arena wrap, seeded procedural arenas.
- AI bots across four difficulty tiers; free-for-all and team modes; Movie
  Mode all-AI attract with periodic arena regeneration.
- 100% procedural rendering (immediate-mode + HDR glow) and 100% synthesized
  audio — no art or sound assets anywhere.
- LAN multiplayer: host-authoritative ENet, UDP auto-discovery, client-side
  prediction with input-replay reconciliation.
- Internet multiplayer via the repo's own relay/master server: room codes,
  online server browser, no port forwarding, no platform services.
- CI: five headless test suites on every push; Linux/Windows/macOS exports
  and zipped GitHub Releases on tags.

Proudly Made in Nebraska. Go Big Red! 🌽 https://xkcd.com/2347/
