# Changelog

All notable changes to **XSpaceWar-AI**.

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
