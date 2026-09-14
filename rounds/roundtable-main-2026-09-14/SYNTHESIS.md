# FlatlineRoundtable Synthesis — Code Review of `main` branch

**Project**: XSpaceWar-AI (https://github.com/CryptoJones/XSpaceWar-AI)  
**Date**: 2026-09-14  
**Target**: `main` branch @ commit `20c5697` (release v5.0.0+)  
**Quorum**: 13 of 14 lanes answered (12 distinct frontier lineages)  
**Execution Host**: Pluto (`roundtable --each -j 15`)

---

## 1. Review Panel Roster

| Lane | Laboratory / Lineage | Model ID | Response Size | Status |
| :--- | :--- | :--- | :--- | :--- |
| **HAL9000** | Anthropic | `opus` (Claude Code CLI) | 21,140 chars | Completed |
| **GLaDOS** | NVIDIA | `nvidia/nemotron-3-ultra-550b-a55b` | 14,945 chars | Completed |
| **Joshua** | xAI | `x-ai/grok-4.6` | 9,055 chars | Completed |
| **Cerebex** | Z.AI | `z-ai/glm-5.3-flash` | 8,178 chars | Completed |
| **Cortana** | Anthropic | `fable` (Claude Code CLI) | 7,801 chars | Completed |
| **MUTHUR** | Moonshot AI | `moonshotai/kimi-k2.6` | 7,518 chars | Completed |
| **SHODAN** | OpenAI | `gpt-5.6-sol` (Codex CLI) | 6,286 chars | Completed |
| **MasterControl** | Mistral AI | `mistralai/mistral-large-2512` | 3,454 chars | Completed |
| **TheDixieFlatline** | Google | `gemini-3.1-pro-high` (Antigravity CLI) | 3,453 chars | Completed |
| **Neuromancer** | DeepSeek | `deepseek/deepseek-v4-flash` | 3,280 chars | Completed |
| **Multivac** | Nous / Meta | `nousresearch/hermes-4-405b` | 3,098 chars | Completed |
| **Proteus** | Amazon | `amazon/nova-pro-v1` | 2,860 chars | Completed |
| **SELMA** | NVIDIA | `nvidia/nemotron-3-super-120b-a12b` | 1,828 chars | Completed |
| **Colossus** | Local (Pluto) | `qwen3.8-27b` | 0 chars | Silent (spent budget on reasoning) |

---

## 2. Key Findings Summary & Convergence Matrix

| # | Severity | Finding | Convergent Lanes | Code Verified |
| :-: | :--- | :--- | :--- | :-: |
| **1** | 🔴 **CRITICAL** | **Remote NaN Injection via Client Inputs (`u`)**: `clampf(NaN, -1.0, 1.0)` evaluates to `NaN` in Godot, corrupting ship kinematics, angle, velocity, and position into an unkillable ghost ship that desyncs snapshots. | **SHODAN, HAL9000, Cortana, GLaDOS, Cerebex** (5 lanes) | ✅ Verified in `net_protocol.gd:101` |
| **2** | 🔴 **CRITICAL** | **Unbounded Immortal Torpedo Accumulation**: Default `torpedo_life == 0` causes endless torpedoes on toroidal arenas with no world population cap, leading to $O(N^2)$ collision checks and snapshot packet overflow past 4KB. | **HAL9000, SHODAN, Joshua, Cerebex, GLaDOS, MUTHUR** (6 lanes) | ✅ Verified in `spawn_system.gd:175` |
| **3** | 🟠 **HIGH** | **Non-Atomic Banfile Overwrite**: `FileAccess.open(_banfile, FileAccess.WRITE)` truncates `--banfile` to 0 bytes before writing; process interrupt, crash, or SIGTERM erases all persistent bans. | **TheDixieFlatline, HAL9000, Cerebex, GLaDOS, Joshua, MasterControl** (6 lanes) | ✅ Verified in `dedicated_main.gd:214` |
| **4** | 🟠 **HIGH** | **`_last_hello_tick` Unbounded Growth & Post-Restart Lockout**: Dictionary never prunes IPs, causing memory leak. When `world.tick` resets to 0 on match restart, negative delta (`0 - old_tick < 3`) locks out rejoining players for up to thousands of ticks. | **TheDixieFlatline, SELMA, HAL9000, Cerebex, GLaDOS, Cortana** (6 lanes) | ✅ Verified in `net_host.gd:41, 284` |
| **5** | 🟠 **HIGH** | **`_on_session_rebuilt` Skips Resets on Empty Peers**: Early return when `_peers.is_empty()` skips resetting `_ev_tick = -1` and `aim.reset()`, carrying stale tick sequence and analyzer state into the next match. | **HAL9000** | ✅ Verified in `net_host.gd:62-67` |
| **6** | 🟡 **MEDIUM** | **Stale Thrust IDs in Snapshots**: `NetHost._broadcast_snapshot()` iterates over retained event buffer (`session.world.events`) rather than current-tick events, sending duplicate/stale thrusting ship IDs. | **HAL9000, SHODAN** (2 lanes) | ✅ Verified in `net_host.gd:186` |
| **7** | 🟡 **MEDIUM** | **Lost Match Recording on Server Exit**: In-progress `.xsr` replay buffer is only written to disk on generation transitions in `_tick()`. A shutdown or SIGTERM drops the active match recording. | **HAL9000, GLaDOS** (2 lanes) | ✅ Verified in `dedicated_main.gd` |
| **8** | 🟡 **MEDIUM** | **AimAnalyzer False Positive on Fire + Hyperspace Chord**: Measuring aim against ship position after hyperspace jump distorts angle calculations, triggering false aim warnings. | **HAL9000, SHODAN** (2 lanes) | ✅ Verified in `aim_analyzer.gd` |

---

## 3. Detailed Technical Breakdown & Adjudication

### Finding 1: Remote NaN Injection via Client Inputs (🔴 Critical)
- **Location**: `src/net/net_protocol.gd:101`
- **Mechanism**:
  ```gdscript
  ship.in_turn = clampf(float(inp.get("u", 0.0)), -1.0, 1.0)
  ```
  In IEEE-754 floating point arithmetic and GDScript, `NaN < -1.0` is `false`, and `NaN > 1.0` is `false`. Therefore `clampf(NaN, -1.0, 1.0)` evaluates to `NaN`.
  Once `ship.in_turn = NaN`:
  - `ship.angle += ship.in_turn * turn_rate * dt` becomes `NaN`
  - `ship.facing()` produces `Vector2(NaN, NaN)`
  - `ship.pos` and `ship.vel` propagate `NaN`
  - Collision tests with `NaN` evaluate to `false`, rendering the ship invulnerable to torpedoes, asteroids, and stars.
  - The authoritative host broadcasts `NaN` position in snapshots, corrupting client viewports.
- **Remediation**:
  ```gdscript
  var u = float(inp.get("u", 0.0))
  ship.in_turn = clampf(u, -1.0, 1.0) if is_finite(u) else 0.0
  ```

---

### Finding 2: Uncapped Immortal Torpedo Population (🔴 Critical)
- **Location**: `src/sim/systems/spawn_system.gd:175`, `src/sim/sim_world.gd:100`
- **Mechanism**:
  With `config.torpedo_life == 0` (the default setting), torpedoes never decay. On toroidal maps, missed shots enter perpetual orbit. As players and bots fire continuously (enabled by `ammo_regen_cooldown`), the active torpedo count in `world.torpedoes` grows monotonically without ceiling.
  - At 60Hz: `collision_system.gd` executes $O(T \times B + T \times S + T^2)$ distance calculations every tick.
  - At 20Hz: `snapshot_of()` serializes the entire array of torpedoes.
  Eventually, the snapshot byte size exceeds `MAX_CLIENT_PACKET = 4096`, causing all connected clients to reject snapshots as malformed/oversized packets and drop.
- **Remediation**:
  Enforce a hard world cap and/or per-ship active torpedo cap in `spawn_system.gd`:
  ```gdscript
  const MAX_ACTIVE_TORPEDOES := 256
  # In fire_torpedo:
  if world.torpedoes.size() >= MAX_ACTIVE_TORPEDOES:
      return
  ```

---

### Finding 3: Non-Atomic Banfile Overwrite (🟠 High)
- **Location**: `server/dedicated_main.gd:214-221`
- **Mechanism**:
  ```gdscript
  var f := FileAccess.open(_banfile, FileAccess.WRITE)
  ```
  `FileAccess.WRITE` truncates the file to 0 bytes immediately upon opening. If the server is terminated, interrupted, or killed by OS during disk sync, the persistent ban list is completely lost.
- **Remediation**:
  Write to a temporary file in the same directory (`_banfile + ".tmp"`), flush and close, then atomically rename over `_banfile` using `DirAccess.rename_absolute()`.

---

### Finding 4: `_last_hello_tick` Unbounded Growth & Post-Restart IP Lockout (🟠 High)
- **Location**: `src/net/net_host.gd:41, 284-287`
- **Mechanism**:
  1. **Memory leak**: Incoming client IP addresses are recorded in `_last_hello_tick[addr] = now_tick` and never pruned.
  2. **Rejoin lockout**: When a match completes and regenerates, `world.tick` restarts at `0`.
     ```gdscript
     if now_tick - int(_last_hello_tick.get(addr, -1000000)) < MIN_HELLO_GAP_TICKS:
         return
     ```
     If an IP had sent a packet at tick `5000` in the prior game, `0 - 5000 = -5000`. Since `-5000 < 3` is `true`, the IP is throttled until the new match advances past tick 5000 (over 80 seconds).
- **Remediation**:
  1. Clear `_last_hello_tick` when the session regenerates.
  2. Guard against negative tick diffs:
     ```gdscript
     var diff := now_tick - int(_last_hello_tick.get(addr, -1000000))
     if diff >= 0 and diff < MIN_HELLO_GAP_TICKS:
         return
     ```
  3. Periodically purge entries older than 60 ticks.

---

### Finding 5: `_on_session_rebuilt` Early Return Resets (🟠 High)
- **Location**: `src/net/net_host.gd:62-67`
- **Mechanism**:
  ```gdscript
  func _on_session_rebuilt() -> void:
      if not _open or _peers.is_empty():
          return
      _inputs.clear()
      _acked.clear()
      _ev_tick = -1
      aim.reset()
  ```
  If no human clients are connected (e.g. Movie Mode attract or dedicated server waiting for players), `_peers.is_empty()` returns before clearing `_inputs`, `_acked`, resetting `_ev_tick = -1`, and resetting `aim`.
- **Remediation**:
  Perform internal state resets BEFORE checking `_peers.is_empty()`:
  ```gdscript
  func _on_session_rebuilt() -> void:
      _inputs.clear()
      _acked.clear()
      _ev_tick = -1
      aim.reset()
      if not _open or _peers.is_empty():
          return
  ```

---

### Finding 6: Stale `thrust_ids` in Snapshots (🟡 Medium)
- **Location**: `src/net/net_host.gd:185-188`
- **Mechanism**:
  `session.world.events` retains events across multiple ticks (up to `MAX_EVENTS = 128`).
  Scanning `for ev in session.world.events:` without filtering by `ev["tk"] == session.world.tick` includes ships that thrust in previous ticks and sends duplicates.
- **Remediation**:
  Filter by `ev.get("tk") == session.world.tick` or check `ship.in_thrust` directly from the live ship state.

---

### Finding 7: In-progress Match Recording Lost on Shutdown (🟡 Medium)
- **Location**: `server/dedicated_main.gd:170-175`
- **Mechanism**:
  Match recording evidence (`_recorder`) is only finalized when a match generation ends. A graceful shutdown (`quit`) or SIGTERM drops the current match's recording.
- **Remediation**:
  Add an explicit `_notification(what)` handler in `dedicated_main.gd` catching `NOTIFICATION_WM_CLOSE_REQUEST` and calling `_finalize_recording()`.
