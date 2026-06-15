# XSpaceWar-AI — High-Level Code Review

Reviewer: Hermes (automated review)
Date: 2026-06-14
Commit reviewed: 5dc5595 (release v2.3.0)
Engine: Godot 4.6 / GDScript · License: Apache-2.0

---

## 0. Resolution log (post-review follow-up, 2026-06-15)

Every prioritized recommendation below has been actioned. Summary:

- **P1 — relay rate-limit gap (§3.1):** `RelayServer` now applies a per-peer
  per-pump packet cap (`MAX_PACKETS_PER_PUMP_PER_PEER = 64`) and a global room
  ceiling (`MAX_ROOMS = 256`); `relay_tests.gd::_test_room_cap` covers it.
- **P1 — input `q` sequence hardening (§3.2):** `NetHost` now rejects implausible
  forward jumps (`MAX_INPUT_SEQ_GAP = 1024`) while still accepting in-order
  advances, exact retransmits, and far-below values (sequence resets); covered by
  `net_tests.gd::_test_input_sequence_guard`.
- **P1 — tests/CI (§5):** the determinism (`_test_determinism`, `_test_replay`)
  and `unpack()` adversarial tests already existed AND already run in CI
  (`ci.yml` runs `run_tests.gd` + `net_tests.gd`; the harness `quit(1)`s on any
  failed assertion, and GitHub's `-eo pipefail` shell fails the step). Added
  `net_tests.gd::_test_unpack_fuzz` (more malformed shapes + the cap boundary).
- **P2 — `run_tests.gd` split (§4.2):** decomposed into `run_tests.gd` (core
  sim), `combat_tests.gd`, `bot_tests.gd`, `gameplay_tests.gd` (89 checks
  preserved exactly); each is its own CI step.
- **P2 — `main.gd` decomposition (§4.1):** extracted the self-contained modals
  into sub-controllers — `MatchHistoryPanel`, `ReplaysPanel`, `PlayersPanel`
  (1,942 → 1,643 LOC). The input-gate-coupled core (menu/net build, settings
  persistence, the keybind-rebind state machine, credits/race attract glue) was
  deliberately retained — it can't be fully verified headlessly. `ui_smoke.gd`
  exercises the extracted panels.
- **P3 — ban persistence (§3.5):** `--banfile` is now the dedicated server's
  persistent ban store (loaded at boot, rewritten on every console ban/unban).
- **P3 — AimAnalyzer docs (§3.4):** README + console make explicit it never
  auto-bans/kicks (operator acts manually).
- **P3 — InputMap quirk (§7):** code comment added at `sync_input_actions()`.

All headless suites pass (sim 89 across 4 files, net 67, relay 17, audio 10,
i18n 38, aim 11, scene + UI smoke).

---

## 1. Summary

XSpaceWar-AI is a clean-room reimplementation of Ron Frederick's 1992
`xspacewar`: a Newtonian space-fighter for up to 16 ships, with procedural
graphics/audio, host-authoritative multiplayer (LAN + relay), bots, and
replays. ~11,175 LOC of GDScript across 60 `.gd` files.

Overall this is a **well-architected, mature, security-conscious codebase**.
It is noticeably more disciplined than typical hobby Godot projects:
deterministic simulation, a documented wire protocol, host-authoritative
netcode with DoS hardening, and a substantial in-repo test harness. The
findings below are refinements, not rescue work.

Overall grade: **B+ / A-** — solid engineering with a few maintainability
hotspots and some defense-in-depth gaps to close.

---

## 2. Architecture (strong)

Clean layered separation with one-directional dependencies:

- `src/sim/`     — authoritative, render-free, deterministic simulation.
                   `SimWorld` owns state and drives a fixed-order `step()`
                   pipeline across stateless per-phase systems
                   (Gravity/Spawn/Mine/Pickup/Collision/Wrap), extracted
                   from a former god-class in issue #18.
- `src/net/`     — host-authoritative networking; direct (ENet/LAN) and relay
                   transports behind a duck-typed interface; `NetProtocol`
                   wire schema; `NetHost`/`NetClient`.
- `src/render/`  — `WorldView`, camera/particles/sky helpers, audio director,
                   procedural `SoundForge`, nebula shader. No sim logic.
- `src/gameplay/`— behavior-tree `BotController`, `AimAnalyzer`, `GameSession`,
                   `MatchStats`, `Replay`/`ReplayPlayer`.
- `src/ui/`      — `main.gd`, `hud.gd`.
- `server/`      — dedicated + relay server entrypoints (GDScript).
- `tests/`       — `run_tests.gd` harness + sim/net/relay/aim/audio/i18n/camera
                   /scene-smoke/playtest probes.

Determinism is a first-class design constraint: integration order is fixed,
all randomness flows through a single seeded RNG (`SimWorld.rng`), and the
step order is explicitly documented as "do not reorder." Clients rebuild the
arena locally from seed + params (`ArenaGen` is deterministic) and apply
snapshots on top — minimizing bandwidth. This is the right model.

---

## 3. Networking & Security (strong, with gaps)

### Done well
- **Host-authoritative.** Clients send only inputs; the host runs the only
  authoritative `SimWorld`. Correct trust model.
- **Safe deserialization.** `NetProtocol.unpack()` uses `bytes_to_var()` (NOT
  the `_with_objects` variant), so a hostile packet cannot smuggle scripts or
  objects. Explicitly documented.
- **Large-packet DoS guard.** `MAX_CLIENT_PACKET = 4096`; oversized packets are
  rejected *before* the expensive `bytes_to_var()` call (issue #13).
- **Input sanitization on the host.** `filter_name()` whitelists A-Z/0-9/space/
  dash/underscore, caps length at 16, never empty — kills BBCode injection,
  control chars, unrenderable glyphs in scoreboards/kill feed.
- **Connection-flood hardening (issue #13):** per-IP peer cap
  (`MAX_PEERS_PER_IP=4`), per-pump per-peer packet cap
  (`MAX_PACKETS_PER_PUMP_PER_PEER=8`), hello throttle
  (`MIN_HELLO_GAP_TICKS=3`). Loopback/relay exempt so local play is unaffected.
- **Protocol versioning.** `VERSION` constant with a strict equality check on
  HELLO guards against mixed-build desync.
- **Defensive snapshot decode.** Every entry in `apply_snapshot()` checks
  `typeof()` and array arity, skipping truncated/corrupt entries rather than
  crashing.
- **Moderation primitives.** kick/ban by name and (on direct/LAN) by address;
  `_reject()` carefully avoids the stale-sid-rehijack bug across rebuilds.

### Gaps / recommendations
1. **Per-IP cap is bypassable on relay.** `_skip_ip_limits()` exempts relay
   clients (their address is `""`), so the per-IP connection/hello throttling
   does not protect relay-hosted games — the very mode most exposed to the
   public internet. Consider a relay-side rate limit or a per-room join cap.
   **✅ Resolved (§0):** relay-side per-peer packet cap + global room cap.
2. **No per-input-message rate limiting.** `MAX_PACKETS_PER_PUMP_PER_PEER`
   bounds packets *per pump*, but a client can still send the max every pump
   indefinitely. The input handler does no validation of `q` (sequence)
   beyond monotonicity — a client sending a huge `q` once would pin `_acked`
   high and could suppress subsequent legitimate inputs after a sequence
   reset. Consider clamping/ window-checking the sequence.
   **✅ Resolved (§0):** `MAX_INPUT_SEQ_GAP` window + reset re-base. (Impact was
   limited — `_acked` is per-ship, so the wedge only hit the attacker's own
   ship — but the window closes it as defence-in-depth.)
3. **`apply_input` trusts client floats.** `in_turn` is clamped to [-1,1]
   (good), but `pos`/`vel` are never sent by clients (host-authoritative —
   good). Confirm no code path lets a client influence position directly.
4. **AimAnalyzer is warnings-only.** Anti-cheat surfaces anomalies to the host
   UI but takes no action. Fine as a design choice; document it so operators
   don't assume automatic enforcement. **✅ Resolved (§0):** README + console
   state it never auto-bans/kicks.
5. **Ban list is in-memory only.** Bans (`_ban_names`, `_ban_addrs`) do not
   persist across server restarts. For dedicated servers, consider persisting.
   **✅ Resolved (§0):** `--banfile` is now a load-and-save ban store. (Callsign
   bans persist; address bans stay transport-ephemeral by design.)

---

## 4. Maintainability hotspots

1. **`src/ui/main.gd` — 1,942 LOC.** By far the largest file; a UI god-object.
   Strongest candidate for decomposition (screen/menu controllers, settings,
   match-flow glue). High change-frequency files this large accrue bugs.
   **✅ Partially resolved (§0):** MatchHistory/Replays/Players panels extracted
   to sub-controllers (now 1,643 LOC); input-coupled core deliberately retained.
2. **`tests/run_tests.gd` — 1,090 LOC.** Monolithic harness; splitting per
   domain would improve failure locality and parallelizability.
   **✅ Resolved (§0):** split into core sim / combat / bot / gameplay suites.
3. **`src/render/world_view.gd` — 621 LOC** after the issue #26 split — still
   large; watch for further growth.
4. **Linear scans by id.** `body_by_id`/`ship_by_id` are O(n) loops. Fine at
   16 ships / small body counts, but if entity counts ever grow, an id→object
   dict would help. Currently a non-issue at design scale.

---

## 5. Testing (strong for the genre)

In-repo headless harness (`run_tests.gd`) plus dedicated suites: sim/net/relay/
aim/audio/i18n, camera probe, playtest probe, scene smoke, screenshot. Net
tests are substantial (~587 LOC). This is well above typical indie-game
coverage. Suggestions:
- Adversarial decode coverage already exists in `net_tests.gd`: garbage bytes
  rejected (`unpack([9,9,9])`, `unpack(var_to_bytes("nope"))`), malformed/too-short
  /wrong-typed snapshot entries skipped without crashing, and oversized packets
  rejected at the host cap (`MAX_CLIENT_PACKET + 1`). These run in CI (the
  `net_tests.gd` step). `_test_unpack_fuzz` was added for more malformed shapes
  and the exact cap boundary; randomized/property fuzzing remains a future nicety.
- Determinism is pinned by two CI-gated tests: `run_tests.gd::_test_determinism()`
  drives two same-seed worlds through an identical 600-step scripted input
  stream and asserts a bit-identical end state (`pos delta == 0.0`), and
  `gameplay_tests.gd::_test_replay()` records a real match, serializes it, and
  replays it into a fresh world demanding a bit-exact final state. Both run on
  every push/PR via `ci.yml` (the harness exits non-zero on any failed check).

---

## 6. Internationalization

`project.godot` declares locales `es, fr, zh_CN, ar, hi` (incl. RTL Arabic).
Good reach. Verify the procedural HUD/score rendering handles RTL and CJK
glyph widths correctly (font atlas built via `tools/build_fonts.py`).

---

## 7. Notable design quirks (not bugs)

- **Input actions populated at runtime.** `xsw_*` actions in `project.godot`
  have empty event arrays; bindings flow from `settings.cfg`/rebind panel into
  Godot's InputMap at runtime via `sync_input_actions()` (issue #25). The cfg
  remains source of truth — anyone reading `project.godot` alone will be
  confused; this is documented but worth a code comment near the loader.
  **✅ Resolved (§0):** comment added at `WorldView.sync_input_actions()`.
- **Torpedoes fly forever by default** (`torpedo_life` default 0) until they
  hit something — intentional, matches the original game.
- **Events accumulate (tick-stamped) rather than clear per step**, with a
  512→256 cap, so multi-step driver passes (fast replay) lose nothing.

---

## 8. Prioritized recommendations

All items below are now done — see the Resolution log (§0) for specifics.

P1 (security/correctness):
- ✅ Close the relay-mode rate-limit gap (per-peer packet cap + room cap).
- ✅ Harden input `q` sequence handling against jumps/resets.
- ✅ `unpack()` adversarial + determinism tests confirmed CI-gated; fuzz expanded.

P2 (maintainability):
- ✅ Decompose `src/ui/main.gd` — extracted MatchHistory/Replays/Players panels
  (1,942 → 1,643 LOC); input-coupled core retained (see §0).
- ✅ Split `tests/run_tests.gd` per domain (combat / bot / gameplay).

P3 (polish):
- ✅ Persist dedicated-server ban lists (`--banfile` is now the store).
- ✅ Document AimAnalyzer as warnings-only for operators.
- ✅ Add a code comment at the InputMap loader explaining the empty-events quirk.

---

## 9. Verdict

A clean, deterministic, security-aware multiplayer game codebase that already
applies practices many production teams skip (safe deserialization, DoS
hardening, host authority, determinism discipline, a real test harness). The
work remaining is incremental: one large UI file to break up, a couple of
netcode defense-in-depth gaps to close, and a few targeted tests to lock in
the guarantees the README already promises.
