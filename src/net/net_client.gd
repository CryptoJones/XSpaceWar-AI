class_name NetClient
extends RefCounted
## Client side of LAN multiplayer. Connects to a NetHost, rebuilds the arena
## locally from the seed + params in MSG_WELCOME (ArenaGen is deterministic),
## then applies host snapshots and dead-reckons entities between them. Local
## key state is forwarded to the host every step; the host owns all gameplay.
##
## Owns a shell GameSession so WorldView/Hud can render it unchanged. The
## session is never update()d here — its world is written by snapshots.

enum State { CONNECTING, READY, FAILED }

const CONNECT_TIMEOUT := 6.0
const MAX_SERVICE_EVENTS := 64

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
	# Surface queued one-shot events + sustained thrust flames to the renderer.
	world.events.clear()
	for ev in _pending_events:
		world.events.append(ev)
	_pending_events.clear()
	for sid in _last_thrusting:
		var s := world.ship_by_id(int(sid))
		if s != null and s.alive:
			world.events.append({"type": "thrust", "ship": int(sid), "pos": s.pos})

	_extrapolate(world, dt)

	if not local_input.is_empty():
		_server.send(NetProtocol.CH_STATE,
			NetProtocol.pack(NetProtocol.MSG_INPUT, local_input), 0)

## Dead-reckon between snapshots: orbiting bodies advance kinematically and
## ships/torpedoes coast under gravity. The next snapshot corrects any drift.
func _extrapolate(world: SimWorld, dt: float) -> void:
	world.time += dt
	world._advance_bodies(dt)
	for s in world.ships:
		if not s.alive:
			continue
		s.vel += world.gravity_accel(s.pos) * dt
		s.pos += s.vel * dt
	for t in world.torpedoes:
		if world.config.torpedo_gravity:
			t.vel += world.gravity_accel(t.pos) * dt
		t.pos += t.vel * dt

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
				var fx := NetProtocol.apply_snapshot(session.world, data)
				_pending_events.append_array(fx["e"])
				_last_thrusting = fx["th"]

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
