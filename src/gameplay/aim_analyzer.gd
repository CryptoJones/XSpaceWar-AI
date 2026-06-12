class_name AimAnalyzer
extends RefCounted
## Host-side aim-anomaly heuristics (issue #4). The host runs the authoritative
## sim and sees every input, so it can watch for statistically impossible play:
##   * near-zero aim variance — shots that are perfectly on-target far more
##     often than a human hand manages while both ships maneuver;
##   * sub-human acquisition — firing within the human reaction floor of a
##     target first entering the aim cone;
##   * seam tracking — aim that stays glued to a target as it teleports across
##     the toroidal wrap edge (a human loses it for a beat).
##
## This NEVER bans. It raises a host-side warning a human reviews — and here a
## flag is genuinely just a prompt to look: perfect input isn't even winning
## play (a frame-perfect bot went 1W-9L vs Veterans), so anomalous aim is a
## curiosity, not a verdict. Thresholds are deliberately conservative and only
## trip on a meaningful sample. Feed it one authoritative step at a time via
## observe(); read report()/flagged() for the surface.

const FIRE_CONE := deg_to_rad(12.0)   ## "on target" cone, for acquisition timing
const TIGHT_AIM := deg_to_rad(3.0)    ## a near-perfect firing solution
const REACTION_TICKS := 7             ## ~117ms @60Hz — below the human floor
const MIN_SHOTS := 20                 ## never flag on thin data
const TIGHT_FRAC_FLAG := 0.9          ## >=90% sub-3 degree shots = inhuman
const FAST_FRAC_FLAG := 0.5           ## >=50% shots inside the reaction floor
const SEAM_FLAG := 3                  ## locked aim across N wrap seams

## Per-ship running tallies (kept tiny — sums, not sample arrays).
class Track:
	var shots := 0
	var tight_shots := 0
	var fast_acquire := 0
	var seam_locks := 0
	var err_sum := 0.0
	var err_sqsum := 0.0
	var target := -1            ## ship currently held in the aim cone (-1 = none)
	var cone_since := -1        ## world tick that target entered the cone
	var cur_err := PI           ## this tick's aim error, stashed for fire matching
	var last_target := -1
	var last_target_pos := Vector2.ZERO
	var has_last := false

var _tracks := {}              ## ship_id -> Track
var _seen_tick := -1
var _fire_tick := -1           ## highest fire-event tick already counted

func _track(sid: int) -> Track:
	if not _tracks.has(sid):
		_tracks[sid] = Track.new()
	return _tracks[sid]

## Observe one authoritative step. `player_ids` are the human-controlled ships
## to watch (bots are never suspects). Idempotent per world tick; safe to call
## every host update.
func observe(world: SimWorld, player_ids: Array) -> void:
	if world == null or world.tick == _seen_tick:
		return
	_seen_tick = world.tick
	var size := world.config.arena_size
	var wrap := world.config.wrap_edges
	var watch := {}
	for sid in player_ids:
		watch[int(sid)] = true

	# 1) Aim geometry, cone-acquisition clock, and seam-lock detection.
	for sid in watch:
		var s := world.ship_by_id(int(sid))
		var tr := _track(int(sid))
		if s == null or not s.alive:
			tr.target = -1; tr.cone_since = -1; tr.has_last = false
			continue
		var e := _nearest_enemy(world, s)
		if e == null:
			tr.target = -1; tr.cone_since = -1; tr.has_last = false
			continue
		var d := _delta(s.pos, e.pos, size, wrap)
		var err := absf(angle_difference(s.angle, d.angle()))
		tr.cur_err = err
		if err <= FIRE_CONE:
			if tr.target != e.id or tr.cone_since < 0:
				tr.target = e.id
				tr.cone_since = world.tick
		else:
			tr.target = -1
			tr.cone_since = -1
		# Seam lock: the target jumped across a wrap edge this tick, yet aim
		# stayed tight on it — a human can't follow through the seam instantly.
		if wrap and tr.has_last and tr.last_target == e.id:
			var raw := e.pos - tr.last_target_pos
			if (absf(raw.x) > size * 0.5 or absf(raw.y) > size * 0.5) and err <= TIGHT_AIM:
				tr.seam_locks += 1
		tr.last_target = e.id
		tr.last_target_pos = e.pos
		tr.has_last = true

	# 2) Score each new fire as an aim sample (events accumulate -> dedup by tick).
	for ev in world.events:
		var tk := int(ev.get("tk", -1))
		if tk <= _fire_tick or String(ev.get("type", "")) != "fire":
			continue
		var fsid := int(ev.get("ship", -1))
		if not watch.has(fsid):
			continue
		var tr: Track = _tracks.get(fsid)
		if tr == null:
			continue
		var err: float = tr.cur_err
		tr.shots += 1
		tr.err_sum += err
		tr.err_sqsum += err * err
		if err <= TIGHT_AIM:
			tr.tight_shots += 1
		if tr.cone_since >= 0 and (world.tick - tr.cone_since) < REACTION_TICKS:
			tr.fast_acquire += 1
	_fire_tick = world.tick - 1   # fire events stamp the pre-increment tick

## Per-watched-player suspicion summary, sorted by ship id. Each entry:
##   {sid, shots, aim_mean_deg, aim_sd_deg, tight_frac, fast_frac, seam_locks,
##    flagged: bool, reasons: Array[String]}
func report() -> Array:
	var out: Array = []
	for sid in _tracks:
		var tr: Track = _tracks[sid]
		if tr.shots == 0 and tr.seam_locks == 0:
			continue
		var n := maxi(1, tr.shots)
		var mean := tr.err_sum / n
		var variance := maxf(0.0, tr.err_sqsum / n - mean * mean)
		var tight_frac := float(tr.tight_shots) / n
		var fast_frac := float(tr.fast_acquire) / n
		var reasons: Array[String] = []
		if tr.shots >= MIN_SHOTS and tight_frac >= TIGHT_FRAC_FLAG:
			reasons.append("inhuman aim — %.0f%% of %d shots under 3 degrees" % [tight_frac * 100.0, tr.shots])
		if tr.shots >= MIN_SHOTS and fast_frac >= FAST_FRAC_FLAG:
			reasons.append("sub-human acquisition — %.0f%% of shots under %dms" % [fast_frac * 100.0, int(REACTION_TICKS * 1000.0 / 60.0)])
		if tr.seam_locks >= SEAM_FLAG:
			reasons.append("aim tracked a target through %d wrap seams" % tr.seam_locks)
		out.append({
			"sid": sid, "shots": tr.shots,
			"aim_mean_deg": rad_to_deg(mean), "aim_sd_deg": rad_to_deg(sqrt(variance)),
			"tight_frac": tight_frac, "fast_frac": fast_frac, "seam_locks": tr.seam_locks,
			"flagged": not reasons.is_empty(), "reasons": reasons,
		})
	out.sort_custom(func(a, b): return int(a["sid"]) < int(b["sid"]))
	return out

## Only the flagged players — the host warning surface.
func flagged() -> Array:
	return report().filter(func(r): return bool(r["flagged"]))

## True if this ship currently trips any heuristic (cheap lookup for UI rows).
func is_flagged(sid: int) -> bool:
	for r in report():
		if int(r["sid"]) == sid:
			return bool(r["flagged"])
	return false

## Reasons this ship is flagged (empty if clean / unknown).
func reasons_for(sid: int) -> Array:
	for r in report():
		if int(r["sid"]) == sid:
			return r["reasons"]
	return []

## Drop a ship's tallies — call when a player leaves or is removed.
func forget(sid: int) -> void:
	_tracks.erase(sid)

## Wipe everything — call on a match rebuild (ship ids are reassigned).
func reset() -> void:
	_tracks.clear()
	_seen_tick = -1
	_fire_tick = -1

func _nearest_enemy(world: SimWorld, s: SimShip) -> SimShip:
	var best: SimShip = null
	var best_d := INF
	var size := world.config.arena_size
	var wrap := world.config.wrap_edges
	for o in world.ships:
		if o == s or not o.alive:
			continue
		if s.team >= 0 and o.team == s.team:
			continue   # teammate
		var d := _delta(s.pos, o.pos, size, wrap).length_squared()
		if d < best_d:
			best_d = d
			best = o
	return best

## Shortest vector from -> to, taking the toroidal wrap when it is enabled.
func _delta(from: Vector2, to: Vector2, size: float, wrap: bool) -> Vector2:
	var d := to - from
	if wrap:
		if absf(d.x) > size * 0.5:
			d.x -= signf(d.x) * size
		if absf(d.y) > size * 0.5:
			d.y -= signf(d.y) * size
	return d
