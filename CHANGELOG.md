# Changelog

All notable changes to **XSpaceWar-AI**.

## [1.7.16] — 2026-06-12

### Fixed
- `git pull` no longer conflicts on `docs/*.png.import`: the docs folder
  is now `.gdignore`d (Godot never imports README images) and the two
  accidentally committed import caches are removed.

## [1.7.15] — 2026-06-12

### Fixed
- **Pilot names are whitelisted** (A-Z 0-9 space dash underscore, max 16,
  never empty) — enforced authoritatively on the host, not just the UI.
  Kills scoreboard BBCode injection from hand-crafted join packets and
  strips unrenderable glyphs (CJK etc. become their alphanumeric residue
  or PILOT).

## [1.7.14] — 2026-06-12

### Added
- **Trusted-server name reclaim** (`--reclaim` on the dedicated server,
  default OFF): rejoining with your name kicks the ghost session and you
  inherit its ship — score and lives intact. Left off for public/Steam
  servers, where a name is not an identity.

### Changed
- Name collisions (no reclaim) now get a **random four-digit tag**
  (PILOT-4827) instead of -2/-3 suffixes.

## [1.7.13] — 2026-06-12

### Added
- **Dedicated server**: `server/dedicated_main.gd` hosts authoritative
  matches headless on a VPS — no human pilot, bots hold every slot,
  players take them over on join and hand them back on leave. Direct
  UDP or relay-registered; full match config via CLI flags.
- **Pilot name field** (MULTIPLAYER tab, persisted): set the name shown
  on every scoreboard.

### Fixed
- Joining with a name already on the roster (live player, un-timed-out
  ghost, or bot callsign) gets a numeric suffix (PILOT-2) instead of a
  scoreboard doppelgänger.
- Server browser no longer counts a phantom host player for dedicated
  servers.

## [1.7.12] — 2026-06-12

### Fixed
- **Giant stars no longer eat fresh spawns**: the spawn/respawn ring now
  scales with the star's actual radius (2.2x + margin) instead of a
  fixed distance, and never sits at the map wall on tiny arenas.

## [1.7.11] — 2026-06-12

### Added
- Movie Mode: **N** cycles the camera to the next living pilot (and back
  to the auto-director after the last).

## [1.7.10] — 2026-06-12

### Changed
- **Torpedoes never expire** — the classic 5-second fuse (authentic to
  1962 Spacewar! and the 1992 xspacewar) is gone by default: torpedoes
  fly until they hit something. Combined with torpedo gravity, missed
  shots now orbit the star as live hazards.

## [1.7.9] — 2026-06-12

### Changed
- Hosting walks UDP 24642–24649 if the default port is taken (LAN
  discovery advertises the actual port, so auto-joins keep working).

## [1.7.8] — 2026-06-12

### Changed
- Ports surfaced where people look: hosting confirms "LAN on UDP 24642",
  the IP/relay fields tooltip their default ports, and the README gains
  a ports reference (24642 game · 24643 LAN discovery · 24645 relay).

## [1.7.7] — 2026-06-12

### Added
- **Lives** (MATCH slider, default 0 = unlimited): with lives set, a
  pilot who burns them all is **eliminated** — no respawn, camera hands
  off to the spectator director (TAB cycles pilots), and the last pilot
  (or team) standing takes the match. Works alongside score/time limits.
- **Editable value boxes**: every slider's readout is now an integer
  input — click, type an exact value, Enter applies it.

## [1.7.6] — 2026-06-12

### Changed
- Score limit slider maximum raised to 1024.

## [1.7.5] — 2026-06-12

### Added
- **Map size slider** (2,000–40,000 units per side, default 40,000):
  arena size is a match setting. The spawn ring scales down on small
  maps, AI roam rings stay inside the boundary, and the value carries
  through net welcomes and replay headers. Movie Mode rolls its own.

### Changed
- **Sliders everywhere**: every numeric MATCH control is now a slider
  with a live value readout — including AI difficulty (Rookie →
  Insane). Zeros read as "endless" / "no clock" / "none"; Ships at 1
  reads "1 (solo)". Mode stays a dropdown (a category, not a quantity).

## [1.6.0] — 2026-06-12

### Added
- **Match setup persists**: mode, difficulty, ships, score/time limits,
  respawn, asteroids, star size, planets, and the boundary toggle save
  when a match starts and restore at boot.
- **Timid pilots mine their escape route**: low-aggression bots (any
  personality) drop mines on a pursuer's path while fleeing.

## [1.5.0] — 2026-06-11

### Added
- **Solo practice flights**: Ships = 1 gives you the whole system alone —
  learn the handling, gravity, mines, and boundary modes in peace.
- **Boundary proximity warning**: in lethal-edge matches a pulsing red
  "⚠ BOUNDARY" distance readout appears when the wall is within 2500u.
- **Wrap slingshot feedback**: crossing the seam now plays a rising
  doppler zip and a cyan speed-streak burst.
- Replay browser entries show mode · pilots · duration.

### Fixed
- **Weak-GPU guard**: bottom-tier adapters (Intel UHD GT1-class,
  software rasterizers) auto-disable HDR glow, which could stall the
  driver and freeze the window; README documents the
  `--rendering-method gl_compatibility` fallback.

## [1.4.0] — 2026-06-11

### Fixed
- **Ships no longer jump from point to point.** The sim runs at a fixed
  60Hz and the renderer drew raw tick positions; now every entity AND
  the camera render at positions interpolated between sim ticks, every
  display frame — silky motion at any refresh rate.

### Added
- **Star size slider** (MATCH, 25 = classic): 0.2×–4× — mass, gravity,
  kill zone, and visual size scale together.
- **Planets control** (0–6, default 2): 0 = no planets at all.
- **Wrap slingshot**: with lethal edges off, crossing the map seam
  doubles your speed (ships, torpedoes, mines, pickups — capped).
- README badges (CI, release, license, Godot, platforms, Codeberg
  mirror).

## [1.3.0] — 2026-06-11

### Added
- **Lethal map edges** (MATCH → Boundary): the border becomes a thick
  pulsing red wall of death instead of wrapping — ships crossing it are
  destroyed; bots steer back from it. Honored by net clients and replays.
- **Killcam**: while waiting to respawn, the camera rides your killer.
- **Ping readout**: net clients show their measured round-trip in the HUD
  banner ("· 23 ms") and the F3 overlay.
- **Follow-cam cycling**: TAB while spectating or in a replay locks the
  camera to each pilot in turn; the banner names who you're following.
- README Thanks section for the play testers.

## [1.2.0] — 2026-06-11

### Added
- **AI temperament**: every pilot rolls two dials per match — **roam**
  (1 hugs the star, 100 prowls out to 6× the spawn ring) and
  **aggression** (1 flees from ships, 100 hunts relentlessly). The fleet
  now spreads across the playfield hunter-killer style instead of
  swarming the gravity well. Deterministic per seed.
- **Match history & career stats** (OPTIONS → MATCH HISTORY…): every
  finished match recorded with standings; career matches/wins/K/D.
- **16 distinct FFA ship colors** (no repeats up to a full lobby), with
  the **scoreboard and kill feed color-coded** to match; your minimap
  dot is always **dark red**.
- Minimap shows **armed mines** (blinking red) and **supply pickups**.
- **Team-sector spawns**: teams spawn and respawn together on their own
  side of the ring.
- Movie Mode mixes bot skill per pilot (rookies among aces).
- Minimap toggle is a rebindable key listed in the bindings UI;
  KEY BINDINGS button on the menu's main row.
- Sim performance regression guard (worst-case 16 bots + dense rocks
  must stay under 4ms/step).
- README gameplay screenshots.

## [1.1.0] — 2026-06-11

### Added
- **Respawn cooldown is a match setting** (1–15s, default 6) — honored by
  net clients and replays.
- Credits: Play Testers — Patrick Hannah, Adam Testagrossa, Trevor Flurry.

### Changed
- **The menu is redesigned into tabs** — MATCH / MULTIPLAYER / OPTIONS —
  replacing the single crowded column (panel went from 519×936 to
  636×658). Title, status, and the QUIT/CREDITS/PLAY row stay always
  visible; sliders get full width; the server list got taller.

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
