# Changelog

All notable changes to **XSpaceWar-AI**.

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
