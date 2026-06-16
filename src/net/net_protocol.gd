class_name NetProtocol
extends RefCounted
## Wire protocol for host-authoritative multiplayer.
##
## Messages are `[type, payload]` arrays encoded with var_to_bytes (and decoded
## with bytes_to_var — never the *_with_objects variants, so a hostile packet
## can't smuggle in scripts/objects). Channel 0 carries reliable control
## traffic (hello/welcome/reject); channel 1 carries the unreliable-sequenced
## state stream (inputs up, snapshots down).
##
## The host runs the only authoritative SimWorld. Clients rebuild the arena
## locally from the seed + params (ArenaGen is deterministic), then apply
## snapshots on top and dead-reckon between them.

# BUMP THIS on ANY wire-schema change (welcome/snapshot/input fields) —
# the strict equality check is the only thing standing between mixed
# builds and silent desync.
const VERSION := 7

## Callsign whitelist: A-Z 0-9 space dash underscore, max 16, never empty.
## Applied authoritatively on the HOST (clients can send anything) — this is
## what keeps BBCode injection, control characters, and unrenderable glyphs
## out of every scoreboard and kill feed.
## Parse "ip" / "ip:port" (one home for the three places that need it —
## the dedicated server's copy had already drifted a validation guard).
static func parse_addr(txt: String, default_port: int) -> Dictionary:
	var t := txt.strip_edges()
	if t == "":
		return {}
	var ip := t
	var port := default_port
	if ":" in t:
		var parts := t.rsplit(":", false, 1)
		ip = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = int(parts[1])
	return {"ip": ip, "port": port}

static func filter_name(raw: String) -> String:
	var up := raw.strip_edges().to_upper()
	var out := ""
	for ch in up:
		var c := ch.unicode_at(0)
		if (c >= 65 and c <= 90) or (c >= 48 and c <= 57) \
				or ch == " " or ch == "-" or ch == "_":
			out += ch
		if out.length() >= 16:
			break
	return out.strip_edges()

static func sanitize_name(raw: String) -> String:
	var out := filter_name(raw)
	return out if out != "" else "PILOT"

enum {
	MSG_HELLO = 1,      ## client -> host: {v, name, spec?}
	MSG_WELCOME = 2,    ## host -> client: {v, id, seed, prm, mode, dif, gen, ros}
	MSG_REJECT = 3,     ## host -> client: {why}
	MSG_INPUT = 4,      ## client -> host: {q, u, t, f, h, m} (q = input sequence)
	MSG_SNAPSHOT = 5,   ## host -> client: see snapshot_of()
	MSG_PING = 6,       ## client -> host: {t} (sender's ticks_msec, echoed back)
	MSG_PONG = 7,       ## host -> client: {t} (echo)
}

const CH_CONTROL := 0
const CH_STATE := 1
const CHANNELS := 2

## Renderer-relevant events forwarded inside snapshots.
const FORWARDED_EVENTS := ["explosion", "hyperspace", "fire", "kill"]

static func pack(type: int, payload: Dictionary) -> PackedByteArray:
	return var_to_bytes([type, payload])

## Largest inbound packet the host will deserialize from a client. Client
## hellos/inputs/pings are all well under 1 KB; anything bigger is a large-
## packet DoS attempt and is rejected before bytes_to_var() (issue #13).
const MAX_CLIENT_PACKET := 4096

## Decode a packet. Returns {"type": int, "data": Dictionary} or {} on garbage.
## ``max_bytes`` rejects oversized packets before the expensive bytes_to_var()
## deserialization; the host passes MAX_CLIENT_PACKET, clients keep the larger
## default to allow full snapshots.
static func unpack(bytes: PackedByteArray, max_bytes: int = 1048576) -> Dictionary:
	if bytes.size() > max_bytes:
		return {}
	var v: Variant = bytes_to_var(bytes)
	if typeof(v) != TYPE_ARRAY:
		return {}
	var arr: Array = v
	if arr.size() != 2 or typeof(arr[0]) != TYPE_INT or typeof(arr[1]) != TYPE_DICTIONARY:
		return {}
	return {"type": int(arr[0]), "data": arr[1] as Dictionary}

# --------------------------------------------------------------------------
# Inputs
# --------------------------------------------------------------------------

## Apply a {u, t, f, h} input payload onto a ship for the upcoming step.
static func apply_input(ship: SimShip, inp: Dictionary) -> void:
	ship.in_turn = clampf(float(inp.get("u", 0.0)), -1.0, 1.0)
	ship.in_thrust = bool(inp.get("t", false))
	ship.in_fire = bool(inp.get("f", false))
	ship.in_hyper = bool(inp.get("h", false))
	ship.in_mine = bool(inp.get("m", false))

# --------------------------------------------------------------------------
# Welcome / roster
# --------------------------------------------------------------------------

static func welcome_of(session: GameSession, your_ship_id: int) -> Dictionary:
	var roster := []
	for s in session.world.ships:
		roster.append([s.id, s.team, s.hull_seed, String(session.ship_names.get(s.id, ""))])
	var out := session.world.config.to_wire()
	out.merge({
		"v": VERSION,
		"id": your_ship_id,
		"prm": session.arena_params,
		"mode": session.mode,
		"dif": session.difficulty,
		"gen": session.generation,
		"ros": roster,
	})
	return out

# --------------------------------------------------------------------------
# Snapshots
# --------------------------------------------------------------------------

## Capture the authoritative world state. `thrust_ids` are ships that thrust
## on the most recent step; `events` are one-shots accumulated since the
## previous snapshot (already filtered to FORWARDED_EVENTS); `acks` maps
## player ship id -> last input sequence applied, for client reconciliation.
static func snapshot_of(world: SimWorld, thrust_ids: Array, events: Array,
		acks: Dictionary = {}) -> Dictionary:
	var ships := []
	for s in world.ships:
		ships.append([s.id, s.pos, s.vel, s.angle, s.fuel, s.ammo, 1 if s.alive else 0,
			s.spawn_grace, s.respawn_timer, s.score, s.kills, s.deaths, s.hyperspace_cooldown])
	var torps := []
	for t in world.torpedoes:
		torps.append([t.id, t.owner_id, t.team, t.pos, t.vel, t.age])
	var mines := []
	for m in world.mines:
		mines.append([m.id, m.owner_id, m.team, m.pos, m.vel, m.age])
	var picks := []
	for p in world.pickups:
		picks.append([p.id, p.kind, p.pos, p.vel, p.age])
	var bodies := []
	for b in world.bodies:
		if b.is_orbiting():
			bodies.append([b.id, b.orbit_angle])
	return {
		"k": world.tick, "t": world.time,
		"s": ships, "p": torps, "mn": mines, "pk": picks, "b": bodies,
		"rb": world.removed_body_ids,
		"e": events, "th": thrust_ids, "a": acks,
	}

## Match-flow state rider for snapshots (kept separate from snapshot_of so
## SimWorld stays session-agnostic).
static func match_state_of(session: GameSession) -> Array:
	return [1 if session.match_over else 0, session.restart_timer,
		session.winner_ship, session.winner_team,
		session.match_time, session.time_limit]

static func apply_match_state(session: GameSession, mo: Array) -> void:
	if mo.size() < 4:
		return
	session.match_over = int(mo[0]) == 1
	session.restart_timer = float(mo[1])
	session.winner_ship = int(mo[2])
	session.winner_team = int(mo[3])
	if mo.size() >= 6:
		session.match_time = float(mo[4])
		session.time_limit = float(mo[5])

## Apply a snapshot onto a client-side world. Returns the snapshot's one-shot
## events ("e") and thrusting ship ids ("th") for the renderer.
static func apply_snapshot(world: SimWorld, snap: Dictionary) -> Dictionary:
	world.tick = int(snap.get("k", world.tick))
	world.time = float(snap.get("t", world.time))

	for entry in snap.get("s", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() < 13:
			continue  # truncated/corrupt entry — skip rather than crash
		var s := world.ship_by_id(int(entry[0]))
		if s == null:
			continue
		s.pos = entry[1]
		s.vel = entry[2]
		s.angle = float(entry[3])
		s.fuel = float(entry[4])
		s.ammo = int(entry[5])
		s.alive = int(entry[6]) == 1
		s.spawn_grace = float(entry[7])
		s.respawn_timer = float(entry[8])
		s.score = int(entry[9])
		s.kills = int(entry[10])
		s.deaths = int(entry[11])
		s.hyperspace_cooldown = float(entry[12])

	world.torpedoes.clear()
	for entry in snap.get("p", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() < 6:
			continue
		var t := SimTorpedo.new()
		t.id = int(entry[0])
		t.owner_id = int(entry[1])
		t.team = int(entry[2])
		t.pos = entry[3]
		t.vel = entry[4]
		t.age = float(entry[5])
		t.life = world.config.torpedo_life
		t.radius = world.config.torpedo_radius
		world.torpedoes.append(t)

	world.mines.clear()
	for entry in snap.get("mn", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() < 6:
			continue
		var m := SimMine.new()
		m.id = int(entry[0])
		m.owner_id = int(entry[1])
		m.team = int(entry[2])
		m.pos = entry[3]
		m.vel = entry[4]
		m.age = float(entry[5])
		m.life = world.config.mine_life
		m.radius = world.config.mine_radius
		world.mines.append(m)

	world.pickups.clear()
	for entry in snap.get("pk", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() < 5:
			continue
		var p := SimPickup.new()
		p.id = int(entry[0])
		p.kind = int(entry[1])
		p.pos = entry[2]
		p.vel = entry[3]
		p.age = float(entry[4])
		p.ttl = world.config.pickup_ttl
		p.radius = world.config.pickup_radius
		world.pickups.append(p)

	# Destroyed asteroids: locally-generated arenas lose the same rocks.
	for rid in snap.get("rb", []):
		if not world.removed_body_ids.has(int(rid)):
			var rb := world.body_by_id(int(rid))
			if rb != null:
				world.bodies.erase(rb)
			world.removed_body_ids.append(int(rid))

	for entry in snap.get("b", []):
		if typeof(entry) != TYPE_ARRAY or entry.size() < 2:
			continue
		var b := world.body_by_id(int(entry[0]))
		if b == null or not b.is_orbiting():
			continue
		b.orbit_angle = float(entry[1])
		var parent := world.body_by_id(b.parent_id)
		if parent != null:
			b.pos = parent.pos + Vector2(cos(b.orbit_angle), sin(b.orbit_angle)) * b.orbit_radius

	return {"e": snap.get("e", []), "th": snap.get("th", []), "a": snap.get("a", {})}
