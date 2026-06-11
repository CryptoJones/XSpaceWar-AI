extends SceneTree
## Standalone entry point for the relay/master service. Run on any box with
## the Godot binary (no display, no game data needed beyond this project):
##
##   godot --headless --path . --script res://server/relay_main.gd -- --port 24645
##
## Players then host/join "online" games pointed at this machine's address.

var relay := RelayServer.new()

func _initialize() -> void:
	var port := RelayProtocol.DEFAULT_PORT
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--port":
			port = int(args[i + 1])
	var err := relay.open(port)
	if err != OK:
		printerr("relay: failed to bind UDP %d (error %d)" % [port, err])
		quit(1)
		return
	print("XSpaceWar relay/master listening on UDP %d" % port)
	process_frame.connect(_tick)

func _tick() -> void:
	relay.pump()
	OS.delay_msec(5)  # ~200Hz service loop; plenty for a forwarding hop
