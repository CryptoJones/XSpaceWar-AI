class_name NetClient
extends RefCounted
## Client side of LAN multiplayer. Connects to a NetHost, rebuilds the arena
## locally from the seed + params in MSG_WELCOME (ArenaGen is deterministic),
## then applies host snapshots and dead-reckons entities between them. Local
## key state is forwarded to the host every step; the host owns all gameplay.
##
## The local ship is *predicted*: every tick its input is applied immediately
## via SimWorld.step_ship_kinematics and buffered with a sequence number; each
## snapshot carries the host's last-applied sequence, so the authoritative
## state is adopted and the still-unacked inputs are replayed on top. Flying
## feels instant while the host stays in charge of weapons and deaths.
##
## Owns a shell GameSession so WorldView/Hud can render it unchanged. The
## session is never update()d here — its world is written by snapshots.

enum State { CONNECTING, READY, FAILED }

const CONNECT_TIMEOUT := 6.0
const MAX_SERVICE_EVENTS := 64
const MAX_PENDING_INPUTS := 120    ## ~2s of unacked inputs before we drop old ones

var session := GameSession.new()   ## world is null until MSG_WELCOME arrives
var state := State.CONNECTING
var error_msg := ""
var player_name := "PILOT"

var _conn := ENetConnection.new()
var _server: ENetPacketPeer
var _open := false
var _timer := 0.0
var _pending_events: Array = []    ## one-shots from snapshots, drained per frame
var _last_thrusting: Array = []    ## ship ids thrusting per the latest snapshot
var _input_seq := 0                ## sequence number of the last input sent
var _pending_inputs: Array = []    ## sent-but-unacked inputs, for replay

func open(ip: String, port := 24642, p_name := "PILOT") -> Error:
	player_name = p_name
	session.movie_mode = false
	session.human_ship_id = -1
	var err := _conn.create_host(1, NetProtocol.CHANNELS)
	if err != OK:
		return err
	_server = _conn.connect_to_host(ip, port, NetProtocol.CHANNELS)
	if _server == null:
		return ERR_CANT_CONNECT
	_open = true
	return OK

func update(dt: float, local_input: Dictionary) -> void:
	if not _open:
		return
	_pump()

	if state == State.CONNECTING:
		_timer += dt
		if _timer > CONNECT_TIMEOUT:
			_fail("connection timed out")
		return
	if state != State.READY or session.world == null:
		return

	var world := session.world
	var own := world.ship_by_id(session.human_ship_id)

	# Sequence, buffer, and send this tick's input (even neutral input — the
	# sequence stream is what reconciliation replays against).
	_input_seq += 1
	var inp := local_input.duplicate()
	inp["q"] = _input_seq
	_pending_inputs.append(inp)
	while _pending_inputs.size() > MAX_PENDING_INPUTS:
		_pending_inputs.pop_front()
	_server.send(NetProtocol.CH_STATE, NetProtocol.pack(NetProtocol.MSG_INPUT, inp), 0)

	# Surface queued one-shot events + thrust flames to the renderer. Remote
	# flames come from the snapshot; our own comes from the live input.
	world.events.clear()
	for ev in _pending_events:
		world.events.append(ev)
	_pending_events.clear()
	for sid_v in _last_thrusting:
		var sid := int(sid_v)
		if sid == session.human_ship_id:
			continue
		var s := world.ship_by_id(sid)
		if s != null and s.alive:
			world.events.append({"type": "thrust", "ship": sid, "pos": s.pos})

	# Predict our own ship now; everyone else dead-reckons.
	if own != null and own.alive:
		if bool(inp.get("t", false)) and own.fuel > 0.0:
			world.events.append({"type": "thrust", "ship": own.id, "pos": own.pos})
		world.step_ship_kinematics(own, float(inp.get("u", 0.0)), bool(inp.get("t", false)), dt)

	_extrapolate(world, dt, own)

	# Smoothing offsets glide out over ~100ms.
	var decay := exp(-10.0 * dt)
	for s in world.ships:
		s.render_pos_offset *= decay
		if s.render_pos_offset.length_squared() < 0.25:
			s.render_pos_offset = Vector2.ZERO

## Dead-reckon between snapshots: orbiting bodies advance kinematically and
## ships/torpedoes coast under gravity. The next snapshot corrects any drift.
## `skip` is the locally-predicted ship (already integrated this tick).
func _extrapolate(world: SimWorld, dt: float, skip: SimShip) -> void:
	world.time += dt
	world._advance_bodies(dt)
	for s in world.ships:
		if not s.alive or s == skip:
			continue
		s.vel += world.gravity_accel(s.pos) * dt
		s.pos += s.vel * dt
	for t in world.torpedoes:
		if world.config.torpedo_gravity:
			t.vel += world.gravity_accel(t.pos) * dt
		t.pos += t.vel * dt

## Convert each ship's snapshot correction into a decaying render offset so
## the drawn position glides to the authoritative one instead of snapping.
## Wrap-aware: a correction across the toroidal seam takes the short path.
func _absorb_corrections(old_vis: Dictionary) -> void:
	var world := session.world
	var size := world.config.arena_size
	for s in world.ships:
		if not s.alive or not old_vis.has(s.id):
			s.render_pos_offset = Vector2.ZERO
			continue
		var off: Vector2 = (old_vis[s.id] as Vector2) - s.pos
		if world.config.wrap_edges:
			if absf(off.x) > size * 0.5:
				off.x -= signf(off.x) * size
			if absf(off.y) > size * 0.5:
				off.y -= signf(off.y) * size
		s.render_pos_offset = off.limit_length(90.0)

## Adopt the snapshot's authoritative own-ship state, drop acked inputs, and
## replay the unacked tail so local control stays ahead of the wire.
func _reconcile(acks: Dictionary) -> void:
	var world := session.world
	var ack := int(acks.get(session.human_ship_id, 0))
	while not _pending_inputs.is_empty() and int(_pending_inputs[0]["q"]) <= ack:
		_pending_inputs.pop_front()
	var own := world.ship_by_id(session.human_ship_id)
	if own == null or not own.alive:
		_pending_inputs.clear()
		return
	for inp in _pending_inputs:
		world.step_ship_kinematics(own, float(inp.get("u", 0.0)),
			bool(inp.get("t", false)), world.config.fixed_dt)

func _pump() -> void:
	for _i in range(MAX_SERVICE_EVENTS):
		var ev: Array = _conn.service(0)
		var type := int(ev[0])
		if type == ENetConnection.EVENT_NONE or type == ENetConnection.EVENT_ERROR:
			break
		match type:
			ENetConnection.EVENT_CONNECT:
				_server.send(NetProtocol.CH_CONTROL,
					NetProtocol.pack(NetProtocol.MSG_HELLO,
						{"v": NetProtocol.VERSION, "name": player_name}),
					ENetPacketPeer.FLAG_RELIABLE)
			ENetConnection.EVENT_DISCONNECT:
				_fail("host closed the connection" if state == State.READY else "connection refused")
				return
			ENetConnection.EVENT_RECEIVE:
				_on_packet(_server.get_packet())

func _on_packet(bytes: PackedByteArray) -> void:
	var msg := NetProtocol.unpack(bytes)
	if msg.is_empty():
		return
	var data: Dictionary = msg["data"]
	match int(msg["type"]):
		NetProtocol.MSG_WELCOME:
			_on_welcome(data)
		NetProtocol.MSG_REJECT:
			_fail(String(data.get("why", "rejected")))
		NetProtocol.MSG_SNAPSHOT:
			if session.world != null:
				var old_vis := {}
				for s in session.world.ships:
					if s.alive:
						old_vis[s.id] = s.pos + s.render_pos_offset
				var fx := NetProtocol.apply_snapshot(session.world, data)
				_pending_events.append_array(fx["e"])
				_last_thrusting = fx["th"]
				_reconcile(fx["a"])
				_absorb_corrections(old_vis)

func _on_welcome(data: Dictionary) -> void:
	var cfg := SimConfig.from_seed(int(data["seed"]))
	var world := SimWorld.new(cfg)
	ArenaGen.populate(world, data.get("prm", {}))
	for entry in data.get("ros", []):
		var s := SimShip.new()
		s.id = int(entry[0])
		s.team = int(entry[1])
		s.hull_seed = int(entry[2])
		s.radius = cfg.ship_radius
		world.ships.append(s)
		var pname := String(entry[3])
		if pname != "":
			session.ship_names[s.id] = pname
	session.world = world
	session.mode = int(data.get("mode", GameSession.Mode.FFA))
	session.difficulty = int(data.get("dif", session.difficulty))
	session.human_ship_id = int(data["id"])
	session.generation = int(data.get("gen", 1))
	state = State.READY

func _fail(why: String) -> void:
	state = State.FAILED
	error_msg = why

func close() -> void:
	if not _open:
		return
	if _server != null and _server.get_state() == ENetPacketPeer.STATE_CONNECTED:
		_server.peer_disconnect()
	_conn.flush()
	_conn.destroy()
	_open = false
