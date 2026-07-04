# Changelog

All notable changes to **XSpaceWar-AI**.

## [Unreleased]

### Fixed
- Controller button bindings now appear in the bindings panel, persist to
  `settings.cfg`, and sync into Godot's `InputMap` alongside keyboard binds.
  (#37)

## [3.2.1] — 2026-07-02

### Fixed
- Dedicated server: the moderation console `_run_command` no longer crashes on an
  empty / whitespace-only line (latent out-of-bounds — the console loop already
  filters these, so it was unreachable in normal play). (#4)

### Added
- `tests/dedicated_tests.gd` — headless coverage for the dedicated-server
  moderation console: kick/ban/unban parsing, `--ban`/comma-list seeding, and the
  `--banfile` persistence round-trip. Wired into CI. (#4)

## [3.2.0] — 2026-07-02

### Changed
- Minor version bump (3.1.43 → 3.2.0).

## [3.1.43] — 2026-07-01

### Added
- **Play tester credit: Noureddine Najah Khalifa.** Added to the in-game rolled
  credits and the README play-testers list, in alphabetical-by-last-name order.

## [3.1.42] — 2026-06-24

### Added
- **Play tester credit: Mark Schantz.** Added to the in-game rolled credits and
  the README play-testers list, in alphabetical-by-last-name order.

## [3.1.41] — 2026-06-16

A weapons-and-respawn release: ordnance is now tunable, dying asks something of
you, and the match-setup screen is split into focused tabs.

### Added
- **Press to respawn.** When your respawn timer elapses you now stay dead until
  you press fire — the HUD prompts `PRESS FIRE TO RESPAWN` instead of counting
  you straight back in. Bots respawn on their own (they hold fire while dead), so
  AI never waits on a keypress. Gated by a new `manual_respawn` flag that defaults
  off for older replays, so pre-feature tapes still play back under the old
  auto-respawn rule.
- **Torpedo & mine lifetime sliders.** Both keep their classic feel by default
  (0 = fly/linger forever for torpedoes; 25 s for mines) and range up to 12
  minutes; the readout shows `m:ss` past a minute.
- **Mine arm-time slider (3–30 s).** Controls when the proximity fuse goes live;
  once armed, enemies always trip it, and teammates/owner only with friendly fire
  on. A mine's lifetime is clamped to never undercut its arm time, surfaced live
  in the lifetime readout as `set → effective`.
- **Gamepad minimap toggle.** Bound to the controller BACK / View button (the
  keyboard `M` toggle was already there).

### Changed
- **Match setup split into MATCH · ARENA · WEAPONS tabs** so the options column
  fits on screen. Friendly fire now lives under WEAPONS, since it governs whether
  your ordnance harms teammates.
- New UI strings (the two new tabs, the weapon labels, and the respawn prompt)
  are translated across all five shipping catalogs (es, fr, zh_CN, ar, hi).

### Internal
- **Net protocol bumped to 7.** The new config fields ride the join handshake's
  welcome payload, so the strict-equality version gate is bumped to keep mixed
  builds from connecting and silently desyncing.

## [3.0.8] — 2026-06-15

A gameplay release — arenas, planets, and the minimap all change substantially,
hence the major-version bump.

### Changed
- **Distance-driven minimap.** The radar now auto-zooms by how far you are from
  the star: tightest at the star (local detail — asteroids, moons, torpedoes),
  easing out to the whole arena at the map edge, smoothly and identically on
  every map size. The star is drawn to scale (exaggerated 4×), and the minimap
  uses a fixed legend — stars yellow, planets green, friendlies blue, enemies
  red — instead of each ship's random colour.
- **Planet system overhaul.** Up to 12 planets (was 2), spread evenly around the
  star and orbiting clockwise; inner planets orbit faster (Keplerian feel) under
  a linear-speed cap of 1/8 the top ship speed, so planets on a huge map barely
  drift. Planet size scales with orbit — the outermost is largest (up to 1.9× the
  star) and each step inward is 12% smaller. Orbit radii scale with the map, so
  planets fan from ~30% of the half-map out to the edge and never share the
  star's central 10,000-unit clear zone. Planets render Earth-like (blue oceans,
  green continents) and are never yellow.
- **Map size range 4,000–160,000.** The arena can now be as small as 4,000 or as
  large as 160,000 units (was capped at 40,000); the menu slider and the
  dedicated-server `--map` flag track the new range.
- **Asteroids fill the arena.** The hazard field now scatters across the whole
  map (cell size scales with the arena) instead of bunching near the star, with
  a bounded rock count at any map size.

### Added
- **Developer testing aids (debug launch only).** Started with `--debug`, the
  pilot can toggle an immortal flag and a freeze-in-place flag; both persist
  across respawns and match restarts. The dedicated server gains `--planets 0-12`.

### Internal
- Continued decomposition: the minimap span math is extracted as a pure,
  unit-tested helper, and the orbit-stability and gravity-sweep tests were
  updated for the new map range (4,000–160,000) and planet layout.

## [2.3.1] — 2026-06-15

### Security
- **Relay server rate-limited.** The standalone relay now caps how many packets
  it acts on per peer per pump and bounds the total number of rooms, closing the
  gap where relay-hosted games bypassed the host's per-IP connection throttling.
- **Client input sequence hardened.** The host rejects implausible jumps in a
  client's input sequence number, so a malformed or malicious value can no
  longer pin the acknowledged sequence and suppress a ship's later inputs.

### Added
- **Dedicated-server bans persist.** `--banfile` is now a load-and-save store —
  console `ban`/`unban` survive a server restart.

### Changed
- **Internal decomposition (no gameplay change).** The simulation test harness
  was split into per-domain suites (core sim / combat / bot AI / gameplay), and
  the `main.gd` UI god-object had its Match History, Replays, and Manage Players
  modals extracted into focused sub-controllers.

### Docs
- Clarified that the host's aim-anomaly heuristics only ever raise a warning for
  an operator to review — they never auto-ban or auto-kick. Documented the
  runtime-populated InputMap actions and expanded the test-suite list.

## [2.3.0] — 2026-06-14

### Changed
- **Player input is now routed through Godot InputMap actions.** Movement,
  firing, and menu controls resolve through named InputMap actions instead of
  scattered hardcoded key checks, giving bindings a single source of truth.
- **Internal architecture refactors (no gameplay change).** `SimWorld` was
  split into per-phase systems (gravity / spawn / mine / pickup / collision /
  wrap); `BotController` was rebuilt as a behavior-tree decision cascade; and
  `WorldView` was split into camera / particle / sky helper modules.

### Fixed
- **Host hardened against inbound denial-of-service.** Inbound packets are now
  size-checked, flood-limited, and rate-limited per source IP, so a malicious
  or malformed peer can no longer exhaust the host.
- **Client crash on malformed snapshot entries.** Snapshot entries are
  bounds-checked before use, preventing an out-of-range crash from a bad packet.
- **LAN discovery could spin on a flooded UDP socket.** The discovery drain is
  now capped per frame.

### Internal
- Added a regression test guarding the `SimConfig` wire round-trip
  (bit-exact, lossless).

## [2.2.0] — 2026-06-14

### Added
- **Friendly fire toggle in match setup.** A new *Friendly fire* CheckButton
  sits below *Boundary* in the match settings tab (default **off**). When off,
  teammates can no longer take blast or torpedo damage from one another, and an
  owner is permanently immune to their own torpedoes (previously only during
  the brief self-hit grace window). When on, all damage applies regardless of
  team. Movie mode always resets friendly fire to off.

### Fixed
- **Owner caught in their own mine blast even with friendly fire off.**
  `_explode_mine` exempted teammates from blast damage but always included the
  owner. With friendly fire off, the owner and teammates are now both exempt.
- **Team ships scattered out of their sector on a blocked spawn retry.**
  `place_in_orbit` fell back to a random angle when a team ship's spawn cell
  was blocked by a lethal body, so a single rock could fling ships anywhere and
  break team clustering (and flake CI). Retries now stay within the team's
  golden-angle sector; the team-spawn test seed is pinned for determinism.

## [2.1.6] — 2026-06-13

### Fixed
- **Self-kills by own mine or torpedo silently dropped from kill feed.** When
  a player shoots their own mine (or flies into their own torpedo), `killer_id`
  is `-1` so no `"kill"` event is emitted — only an `"explosion"` event with
  cause `"mine"` or `"torpedo"`. Neither cause had a handler in the kill feed,
  causing a silent respawn with no history entry. Added handlers for both; they
  fire only on self-kills (enemy kills already produce a visible `"kill"` event).
  The player now sees `"NAME ✕ own mine"` / `"NAME ✕ own torpedo"` at double
  size (since it involves them).

## [2.1.5] — 2026-06-13

### Fixed
- **Team mode: all ships landed on one team** after watching the attract/movie
  loop. `num_teams` was never reset in `start_skirmish()`, so a prior movie-mode
  FFA round (which sets `num_teams = 1`) bled into the next team skirmish,
  making `i % 1 = 0` for every ship. Fixed by always setting `num_teams` at
  skirmish start.

### Changed
- **Kill feed events linger twice as long** — TTL raised from 6 s to 12 s.
- **Events that involve your ship render at double font size** in the kill feed
  so they stand out at a glance.
- **Splash screen (post-credits controls reference) scaled to 50%** — the panel,
  title, controls grid, and "PRESS SPACE BAR" prompt were all oversized on
  1080p displays.
- **Credits rolling title reduced to 85%** (229 pt → 195 pt).
- **Menu credits panel title reduced to 85%** (42 pt → 36 pt).
- AI credit updated: "Claude Fable 5" → "Fable5/Opus4.8".

## [2.1.4] — 2026-06-13

### Fixed
- **Minimap and scoreboard invisible or mispositioned on all platforms.**
  The RTL-mirroring code added in v1.13.0 switched from hardcoded top-left
  anchors to `set_anchors_preset` + `position` for the scoreboard and radar.
  In Godot 4, setting `.position` on an anchored `Control` recomputes the
  internal offsets from the current viewport size, placing controls off-screen:
  the scoreboard landed at x = −336 (invisible left of screen) and the minimap
  at y = −186 (clipped above screen, then rendered over the kill feed).
  Fixed by setting `offset_left/right/top/bottom` directly on each element,
  which places them relative to their anchor points independent of when the
  `CanvasLayer` resolves its viewport rect.

## [2.1.3] — 2026-06-13

### Fixed
- **M and B keybinds (minimap / scoreboard) silently did nothing on macOS.**
  `LineEdit` nodes in the menu (name, IP, relay, code fields) retained keyboard
  focus after the menu hid. The hidden-but-focused `LineEdit` consumed letter-key
  `InputEvent`s via `_gui_input` before they reached `_unhandled_input`, so
  pressing M or B during gameplay had no effect. ESC was unaffected because
  `LineEdit` releases its own focus on ESC first; ship movement was unaffected
  because it polls `Input.is_physical_key_pressed`. Fix: call
  `get_viewport().gui_release_focus()` in `set_menu_visible(false)` so all focus
  is cleared whenever the menu closes. Linux was never affected.

## [2.1.2] — 2026-06-13

### Fixed
- **Team-mode scoreboard rendered blank.** The per-player team tag was emitted as the
  literal text `[T1]`/`[T2]`/`[T3]`, which the scoreboard's BBCode-enabled RichTextLabel
  parsed as an unknown tag — aborting the parse and dropping every row after the header.
  The bracket is now escaped (`[lb]T%d]`), so it renders as plain text and the full board
  (team totals + all player rows) shows in Team mode. Free-for-all was never affected.

## [2.1.1] — 2026-06-13

### Changed
- Credits: added playtesters **Roger Bergling**, **Brad Cramer**, and **John Van Lowe**;
  labeled the header **PLAY TESTERS (ALPHABETICAL)** and sorted the full list by surname.
- Dedication: clarified to "all the nights **gaming** in 90s-era Dickinson, Texas".
- README: added a **Play Testers** section mirroring the in-game credits, and synced the
  README dedication to match the credits.

## [2.0.1] — 2026-06-13

### Changed
- Credits: added **Henry Hannah** and **Kevin Christiansen (PE)** to the playtesters,
  now sorted alphabetically by last name.

## [2.0.0] — 2026-06-13

### Changed
- **First public multi-store launch build.** Functionally the same game as 1.14.0,
  versioned 2.0 as the single baseline build distributed across every storefront —
  Steam, itch.io, AUR, Internet Archive, GameJolt, IndieDB/ModDB,
  and GOG. (Epic Games Store skipped — its ~$100/product self-publishing fee makes it
  non-free.)
- Credits: removed the "Executive Producer" entry.

## [1.14.0] — 2026-06-13

### Added
- **Steam store art set — issue #1 complete.** A full, procedurally-rendered
  store presence under `docs/steam/`, built from the game's own shaders, hulls,
  and nebula with an Orbitron wordmark: capsule (460×215), small capsule
  (231×87), library capsule (600×900), library hero (3840×1240), page
  background, a transparent logo, and five gameplay screenshots. Rendered on
  the Mac mini's M2 Pro for full HDR glow; `tools/render_*.gd` regenerate every
  asset.
- **Gameplay trailer (`docs/steam/trailer.mp4`)** — a six-beat, ~24s montage
  cut from real human-played 4K/60 capture (Metal glow), scored with an
  original cinematic track: a purple-nebula opener, two green-nebula duels, and
  a close on the **WIN / FINAL STANDINGS** board. Replaces the earlier
  locked-camera cut.

### Changed
- **Fresh installs now ship the nebula-maxed sky.** A new install (no
  `settings.cfg`) boots with **nebula = 100, stars = 9** — the look dialed in
  for the trailer — instead of the old near-black default (nebula 0, stars 50).
  Existing players keep their saved settings; the minimap stays on by default.
- Credits: added **Jeremy Zhao** and **Nate Tiller** to the playtesters.

## [1.13.0] — 2026-06-12

### Added
- **Non-Latin localization — Chinese, Arabic (RTL), and Hindi (issue #5
  complete).** Building on the #3 wiring, the default UI font now carries
  per-glyph **fallback fonts** (Noto Sans subsets) so scripts outside Latin
  render instead of tofu — attached to the *existing* default font, so Latin
  text and every HUD symbol are pixel-identical to before; a fallback is
  consulted only for glyphs the base lacks. With the Spanish + French catalogs
  from #3, the game now ships **seven UI languages**.
  - **Simplified Chinese (zh_CN)** — full 159-string catalog + an **83 KB**
    Noto Sans SC subset (318 glyphs; full font ~10 MB).
  - **Arabic (ar)** — full catalog + a **16 KB** Noto Sans Arabic subset.
    Shaping + in-line BiDi are automatic (TextServer). The UI **mirrors RTL**:
    menus/panels flip via `root_node_layout_direction`, and the HUD mirrors by
    hand — scoreboard → top-left, kill feed → top-right, radar → bottom-right,
    watcher hint → bottom-left; centered/graphical elements (bars, off-screen
    arrows) stay put. Mirroring switches live with the language.
  - **Hindi (hi)** — full catalog + a **115 KB** Noto Sans Devanagari subset
    (conjunct shaping via TextServer).
  - All machine-drafted, flagged for native review. `tools/build_fonts.py`
    regenerates the subsets from the catalogs; the i18n test covers every
    locale (now 38 checks: completeness + printf-specifier integrity per
    catalog). Known nit: composed strings like the menu subtitle re-translate
    on boot-in-locale, not on a live in-session language switch.
- **SteamPipe build-delivery scaffolding** (issue #2) — `steam/` SteamPipe
  scripts (`app_build.vdf` + per-platform depot vdfs) and a gated
  `steam-deploy` workflow that, on a published release, fetches the exact
  per-tag artifacts CI already builds and uploads one depot per platform
  (Windows / Linux / macOS). **Inert until armed**: the job is skipped unless
  the repo variable `STEAM_DEPLOY=true`, and all IDs/credentials come from
  secrets (nothing real in git). Setup + default/beta branch strategy in
  `steam/README.md`. No game change — ships nothing until the Steamworks
  account exists. GodotSteam achievements/lobbies remain a separate later
  effort.

## [1.12.1] — 2026-06-12

### Changed
- Credits: added **Beaux Onofrio**, **Nick Onofrio**, and **Shannon (Learn)
  Koski** to the playtesters.

## [1.12.0] — 2026-06-12

### Added
- **Server-side aim-anomaly heuristics — host warnings, never bans.** (issue
  #4) The host runs the authoritative sim and sees every input, so the new
  `AimAnalyzer` watches each connected pilot for statistically impossible play:
  - **near-zero aim variance** — a shooter holding a sub-3° firing solution
    far more often than a human hand can while both ships maneuver;
  - **sub-human acquisition** — firing within the ~117ms reaction floor of a
    target first entering the aim cone;
  - **seam tracking** — aim that stays glued to a target as it teleports
    across the toroidal wrap edge (a human loses it for a beat).
  Each signal is conservative and only trips on a real sample (≥20 shots, or 3
  seam-locks). Flags surface as a ⚠ in the host **MANAGE PLAYERS** panel (with
  the reason and per-pilot aim stats) and in the dedicated console's new
  `watch` command — and that is **all** they do. There is deliberately no
  auto-ban: a flag is a prompt to look, because perfect input isn't even
  winning play here (a frame-perfect bot went 1W–9L vs Veterans), so an
  anomaly is a curiosity, not a verdict. 11 unit tests cover an aimbot
  tripping the flag, a sloppy human staying clean, and cross-seam aim-lock.
- **This closes the implementable scope of issue #4** (kick/ban + replay
  evidence shipped in 1.11.0). Only the Steamworks **VAC** checkbox remains —
  blocked on the partner account. Kernel anticheat stays a non-goal.

## [1.11.0] — 2026-06-12

### Added
- **Multiplayer moderation: host kick/ban + dedicated console + replay
  evidence.** (issue #4) The architecture was already host-authoritative
  (clients send inputs only — speed/teleport/ammo/score hacks can't
  replicate); this adds the removal lever that was missing.
  - **`NetHost`** kick/ban API: `connected_players()`, `kick_ship()`,
    `kick_name()`, `ban_name()` / `unban_name()` / `ban_list()`. A kick sends
    the leaver a reason over the reliable channel (flushed before disconnect)
    and hands their ship back to a fresh bot; a ban also blocks the callsign
    and — on direct/LAN, via the new transport `peer_address()` — the IP
    (relay clients are name-bannable only, since the host never sees their
    address). Bans are enforced at `HELLO`, before any slot is handed out.
  - **GUI host**: a **MANAGE PLAYERS** panel (a PLAYERS button that appears
    in the menu only while hosting) listing connected pilots with KICK / BAN.
    Player callsigns render literally (auto-translate disabled) so a pilot
    named "MODE" isn't localized.
  - **Dedicated server**: a live stdin console — `kick <name>`, `ban <name>`,
    `unban <name>`, `players`, `bans`, `help` — plus `--ban NAME` (repeatable
    / comma-lists) and `--banfile PATH` to seed bans at boot, and a periodic
    connected-roster log.
  - **Replay-based adjudication**: a dedicated-server `--record [DIR]` flag
    records every match as a bit-exact `.xsr` (the existing replay format) for
    cheating evidence, rotated across auto-restarts.
  - All new UI strings localized (es / fr); 11 new netcode tests cover kick →
    re-bot, name-ban + unban, and address-ban of a renamed rejoin.
  - **Deferred to a follow-up** (still #4): server-side aim-anomaly heuristics
    (host-side warnings, never auto-ban) and the Steamworks **VAC** checkbox
    (blocked on the partner account). Kernel anticheat remains a non-goal.

## [1.10.0] — 2026-06-12

### Added
- **Localization (i18n) — the wiring, plus Spanish and French.** (issue #3)
  - Godot `TranslationServer` catalogs under `locale/` (gettext `.po`),
    auto-loaded via `project.godot` `[internationalization]`. The canonical
    string list is `locale/messages.pot` (149 strings); `en` is the source
    language and needs no catalog (lookups fall through to the key).
  - A **Language** selector in OPTIONS (endonyms, never auto-translated),
    persisted to `settings.cfg`. The default follows the OS locale when a
    matching catalog ships, else English. Switching is live — static UI
    re-translates on the spot; the HUD re-resolves every frame.
  - Every menu / options / splash / key-binding / panel string and the core
    HUD (banner, scoreboard, respawn, boundary warning, fuel·ammo·mine bars,
    final standings, network status lines) routes through `tr()`. Format
    templates are translated *before* they are filled, so `%d`/`%s`/`%%`
    survive intact.
  - **Spanish (es)** and **French (fr)** catalogs — machine-drafted and
    flagged for native review (`X-Review-Status: machine-draft`). HUD bar
    labels are abbreviated to fit (e.g. `FUEL`→`COMB.`/`CARB.`).
  - `tests/i18n_tests.gd` (wired into CI): enforces catalog completeness,
    printf-specifier integrity, and live resolution through the
    `TranslationServer` — a half-translated or arg-dropping catalog fails CI.
  - Decision on record: pilot names stay Latin-whitelisted regardless of UI
    language; the Orbitron wordmark and the credits roll stay English.
  - Deferred to issue #5: non-Latin locales (zh-CN / hi / ar) needing Noto
    fallback fonts + an Arabic RTL pass, plus the kill-feed verbs, the "YOU"
    self-label, and the server-browser rows (sentinel- or data-coupled).

## [1.9.2] — 2026-06-12

### Changed
- **Minimum map size is now 2,601 units.** Below that, a maxed Star-size
  slider would swallow the whole arena (its escapable shell wider than
  the playfield). Raising the floor removes that one degenerate corner
  outright — both sliders keep their full range and do exactly what they
  say, with no hidden clamps.

## [1.9.1] — 2026-06-12

### Changed
- **Gravity is honest Newtonian again — the cap is gone.** The escapability
  cap (v1.9.0) bent inverse-square into a constant-force core, which itself
  destabilized orbits and needed a second hack to patch. Both removed.
  Instead the star's **mass is sized to the arena** (a level-design
  parameter, not a physics fudge): `star_mass = 0.35·thrust·spawn_r²/G`, so
  small maps stay playable while gravity is pure `1/r²` at every star size.
  Proven: a still pilot orbits a stable Keplerian ellipse across the whole
  star-size × map-size matrix.
- **Toroidal wrap preserves velocity** — the seam no longer doubles your
  speed. That "slingshot" was free energy that compounded into an
  unrecoverable runaway on small wrapping maps (the "Epstein-drive
  catastrophe"); held thrust is now always recoverable via flip-and-burn,
  exactly like 1962.
- New README **Physics** section documenting all of the above.

## [1.9.0] — 2026-06-12

### Changed
- **The gravity well no longer inflicts death on players** — proven
  across the ENTIRE star-size slider (5–100) × every map size
  (2,000–40,000) via a 36-cell survival sweep:
  - **Escapable everywhere**: gravitational acceleration is hard-capped
    below engine thrust, so a pilot burning away from the star always
    makes headway. Before, a small map's steep core pulled ~1,980 u/s²
    against 900 u/s² of thrust — an inescapable death drag even for a
    ship holding still.
  - **Stable spawns**: ships spawn outside the capped core, in the true
    inverse-square region where circular orbits are stable — a still
    pilot now orbits forever instead of decaying into the sun.
  - Slingshots at range are unchanged.

## [1.8.4] — 2026-06-12

### Added
- Credits: "GitHub / Codeberg Contributors — This Could Be You!"

## [1.8.3] — 2026-06-12

### Fixed
- **Exported builds write logs again**: file logging was only ever on
  for editor/source runs — packaged games logged nothing, which made
  the macOS diagnosis blind. Exports now write
  user://logs/godot.log on every platform (--debug output included).
- macOS release asset is no longer a zip inside a zip — one unzip,
  there's the app.

## [1.8.2] — 2026-06-12

### Fixed
- **Kill feed (and all one-shot effects) work again**: 1.7.26's event
  rework stamped events with the pre-increment tick, so consumers
  skipped every kill/death line, explosion effect, and weapon sound —
  an off-by-one in the consume guard. (Looked Mac-specific in testing,
  but was version skew: the Mac was the only box running the newest
  build.) A scene-level regression test now forces a kill and asserts
  it reaches the feed.

### Added
- **K toggles the kill feed, B toggles the scoreboard** (rebindable,
  persisted) — for those who want a cleaner screen.
- **--debug flag**: launch with `--debug` for the F3 overlay on boot,
  version/adapter banner, kill-feed echo to stdout, and a diagnostics
  line every 5 seconds — made for grabbing logs on test machines.

## [1.8.1] — 2026-06-12

### Fixed
- **macOS packages launch again**: the export now ad-hoc signs the app
  bundle. Godot's export template ships pre-signed; inserting the game
  data invalidated that signature, and Apple Silicon kills invalid-
  signature apps at exec — the misleading ""damaged" and can't be
  opened" dialog. (Until you re-download, the local workaround is:
  codesign --force --deep -s - XSpaceWar-AI.app && xattr -dr
  com.apple.quarantine XSpaceWar-AI.app)

## [1.8.0] — 2026-06-12

**The review-hardened release.** A 9-angle, 26-verifier audit of the whole
project surfaced 33 confirmed findings; v1.7.22 through this release fix
every confirmed correctness bug and the structural causes behind them.
See the batch entries below (1.7.22–1.7.27) for the full list.

## [1.7.27] — 2026-06-12

Code-review fixes, batch 5 (structural):

### Changed
- **One home for match-config wire format**: SimConfig.to_wire/from_wire
  now feed the net welcome, replay headers, and client/replay loaders —
  the hand-synced field lists that shipped two desync bugs are gone.
- **One camera-target resolver**: priority is explicit (own ship > TAB
  choice > killcam > director) with the bleed clamp applied uniformly —
  the if/elif chain that shipped three camera bugs is gone.
- One wrap+slingshot implementation (was five copies — a missed copy
  desynced prediction), one ip[:port] parser (was three, one already
  drifted), one match-start path (was three), one display-name authority
  (feed and kill popups can no longer disagree).

## [1.7.26] — 2026-06-12

Code-review fixes, batch 4b (collision, events, camera, rebinding):

### Fixed
- **Slingshot-speed shots connect**: torpedo-vs-ship/body and
  ship-vs-body collisions are swept along their travel segment, so
  wrap-boosted projectiles and ships no longer tunnel through targets
  (wrap teleports fall back to point tests).
- **No event is ever lost**: sim events accumulate with tick stamps and
  consumers process each exactly once — the kill feed stops dropping
  entries on sub-60fps frames, and fast replay playback keeps all
  explosions/audio/feed lines.
- The Movie Mode director clamps its followed duelist on-screen
  (hyperspace and slingshots can no longer leave the camera staring at
  empty space until the lerp catches up).
- **Rebinding refuses conflicts**: a key already bound to another action
  (or reserved: TAB/N/F3) is rejected with an explanation instead of
  silently double-binding weapons.

## [1.7.25] — 2026-06-12

Code-review fixes, batch 4a (gameplay/session):

### Fixed
- **Team mutual annihilation ends the match** (score decides) instead of
  soft-locking a lives match forever; **solo practice + lives** no longer
  insta-wins in an endless restart loop.
- **Hyperspace is a teleport again, not a resupply**: jumps keep your
  fuel/ammo/mines/cooldowns and grant no invulnerability (the spawn
  helper's full refill + grace was leaking through).
- **Respawns can't materialize into a rock**: spawn placement re-rolls
  away from lethal bodies, and spawn grace now shields against bodies
  like it always did against ships and torpedoes — no more zero-input
  deaths burning lives at hazard 100.
- **Finished-match recordings survive auto-restarts**: the session parks
  the tape before rebuilding the world (sub-60fps frames were capturing
  the new world into the old tape, corrupting and discarding it).
- The Movie Mode attract resets lethal edges/respawn/score/time instead
  of inheriting them from your last skirmish.

## [1.7.24] — 2026-06-12

Code-review fixes, batch 3 (multiplayer UX + ingress hardening):

### Fixed
- **Everyone sees real pilot names now**: roster names ride snapshots
  whenever they change, so existing players learn newcomers' names
  (joins, reclaims, restarts) instead of seeing bot callsigns forever.
- **Name sanitization at every ingress**: client welcome rosters,
  snapshot name updates, replay-file rosters, and the settings-loaded
  host name — markup injection is dead even against modified hosts and
  crafted replays.
- The name field filters as you type without the PILOT-fallback
  mangling; collision tags now fit the 16-character invariant (so
  tagged players can still reclaim).
- **Reclaim no longer orphans a slot** — the probed bot ship is handed
  back when a ghost is reclaimed.
- **Relay-link death hands every ship back to bots** (was: derelicts
  flying their last inputs forever with inflated player counts).
- Relay rooms no longer count the host against capacity (dedicated
  N-ship rooms seat N players; spectators get headroom).
- **Hostile packets can't error-storm the servers**: relay FWD/REGISTER
  fields, LAN-discovery broadcasts, and relay browser lists are
  type-validated before use; corrupt replay files are refused at load
  instead of erroring during playback.
- HOST ONLINE now starts recording when "Record matches" is on.
- Match history can't silently skip a match after switching sessions
  (history key includes the session identity, not just the counter).

## [1.7.23] — 2026-06-12

Code-review fixes, batch 2 (restart lifecycle + protocol):

### Fixed
- **A rejected peer can no longer hijack a live player's ship**:
  _reject now forgets the peer immediately, so the kick's later
  disconnect event can't hand a stale old-generation ship id to a bot.
- **Full dedicated servers no longer kick one player per restart**:
  sessions remember they're dedicated, so rebuilt rosters stay all-bot
  (tested: 2 players on a full 2-slot server survive a restart).
- **The dedicated server now runs a true fixed-step sim** (accumulator
  at fixed_dt) — identical integration to the GUI host, so client
  prediction reconciles cleanly instead of perpetually correcting.
- **Stale snapshots can't corrupt a rebuilt arena**: snapshots are
  generation-tagged and clients drop ones from a previous match
  (in-flight across a restart, their removed-body ids overlap fresh
  ids and deleted live asteroids).
- **Protocol VERSION bumped to 6** (first bump since v0.8.0 despite
  schema growth) with a bump-on-any-schema-change policy comment —
  mixed old/new builds now get a clean "protocol version mismatch"
  instead of silently desyncing.
- The dedicated server announces its relay room code the moment it is
  assigned (was buried in the 30s status line).

## [1.7.22] — 2026-06-12

Code-review fixes, batch 1 (guards and quick kills):

### Fixed
- **CI now fails on failing tests** — the test pipelines lacked
  pipefail, so a suite exiting 1 on [FAIL] still passed; only script
  errors gated. The hole is closed on all five suites.
- **Linux release zips launch out of the box** — artifact download
  strips the executable bit; the release job restores it before zipping.
- **Panels no longer leak input to the live ship**: opening KEY
  BINDINGS / REPLAYS / MATCH HISTORY (or the credits/splash) now gates
  ship input and pauses solo matches exactly like the menu — no more
  thrusting and firing while you rebind, solo or networked.
- **Bots only fire when the shot can land**: the fire gate now checks
  the nose against the lead-aim firing solution instead of the nav
  heading — fleeing/patrolling pilots stop spraying torpedoes away
  from their target.
- **Difficulty affects aggression again**: the preset multiplier had
  been dead since the temperament rework (rookies hunted as hard as
  insane pilots); it now scales each pilot's aggression roll.

## [1.7.21] — 2026-06-12

### Fixed
- **Dead-state camera actually follows now**: a branch-ordering bug left
  the camera frozen near your wreck while dead ("following ghosts") —
  the TAB target and action director branches never ran. Watching works
  through any death; respawn still snaps home.

## [1.7.20] — 2026-06-12

### Fixed
- **Death always hands the camera to someone alive**: environment deaths
  (rocks, the star, the boundary) have no killer to killcam, and used to
  leave you staring at your wreck — now the action director takes over,
  and **TAB/N cycle pilots during any death**, not just elimination.
  Killcam yields to an explicit TAB choice; respawning snaps back to
  your cockpit and resets the watcher state.

## [1.7.19] — 2026-06-12

### Fixed
- Camera probe asserts the on-screen invariant for living ships (corpse
  drift behind the killcam is intended).

## [1.7.18] — 2026-06-12

### Fixed
- **Follow-cam targets can no longer escape the screen**: the bleed-zone
  clamp (previously your own ship only) now protects whatever the camera
  follows — TAB targets, the killcam, eliminated-spectating — with a
  wrap-teleport guard so the interpolated camera doesn't smear.

## [1.7.17] — 2026-06-12

### Fixed
- **TAB cycles pilots everywhere you watch** — movie mode included
  (N still works there too).
- The ELIMINATED message is no longer a center-screen billboard: it's a
  small bottom-right hint, out of the action. Movie Mode shows the same
  quiet "TAB follows a pilot" hint.

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
