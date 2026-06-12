class_name RelayBrowser
extends RefCounted
## One-shot online server browser: connect to a relay, request the room list,
## surface it, hang up. Drive with update(dt); read `done`/`servers`/`error`.

const TIMEOUT := 4.0

var servers: Array = []
var done := false
var error := ""

var _conn := ENetConnection.new()
var _relay: ENetPacketPeer
var _open := false
var _timer := 0.0

func open(ip: String, port: int) -> Error:
	var err := _conn.create_host(1, NetProtocol.CHANNELS)
	if err != OK:
		return err
	_relay = _conn.connect_to_host(ip, port, NetProtocol.CHANNELS)
	if _relay == null:
		return ERR_CANT_CONNECT
	_open = true
	return OK

func update(dt: float) -> void:
	if not _open or done:
		return
	_timer += dt
	if _timer > TIMEOUT:
		_finish("relay timed out")
		return
	for _i in range(64):
		var ev: Array = _conn.service(0)
		var t := int(ev[0])
		if t == ENetConnection.EVENT_NONE or t == ENetConnection.EVENT_ERROR:
			break
		match t:
			ENetConnection.EVENT_CONNECT:
				_relay.send(NetProtocol.CH_CONTROL, NetProtocol.pack(RelayProtocol.LIST, {}),
					ENetPacketPeer.FLAG_RELIABLE)
			ENetConnection.EVENT_DISCONNECT:
				_finish("relay unreachable")
				return
			ENetConnection.EVENT_RECEIVE:
				var msg := NetProtocol.unpack(_relay.get_packet())
				if not msg.is_empty() and int(msg["type"]) == RelayProtocol.SERVERS:
					# Shape-check the untrusted list: keep only Dictionary
					# entries (a hostile relay must not error the menu loop).
					var lv: Variant = (msg["data"] as Dictionary).get("list", [])
					servers = []
					if typeof(lv) == TYPE_ARRAY:
						for entry in lv:
							if typeof(entry) == TYPE_DICTIONARY:
								servers.append(entry)
					_finish("")
					return

func _finish(err: String) -> void:
	error = err
	done = true
	close()

func close() -> void:
	if not _open:
		return
	if _relay != null and _relay.get_state() == ENetPacketPeer.STATE_CONNECTED:
		_relay.peer_disconnect()
	_conn.flush()
	_conn.destroy()
	_open = false
