extends SceneTree
## Dedicated headless server. From the game/ folder:
##   godot --headless -s res://src/net/server_main.gd -- [--port 7777] [--quit-after SECONDS]

const Server = preload("res://src/net/game_server.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(_arg(args, "--port", str(Protocol.DEFAULT_PORT)))
	var quit_after := float(_arg(args, "--quit-after", "0"))
	# The sim ticks at 20 Hz; 120 frames/s keeps tick timing within ~8 ms
	# without spinning a core.
	Engine.max_fps = 120

	var server: GameServer = Server.new()
	root.add_child(server)
	var err := server.start(port)
	if err != OK:
		printerr("[server] could not listen on UDP %d: %s" % [port, error_string(err)])
		quit(1)
		return
	if quit_after > 0.0:
		create_timer(quit_after).timeout.connect(func() -> void:
			print("[server] quit-after reached")
			server.stop()
			quit(0))


func _arg(args: PackedStringArray, name: String, fallback: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i != -1 and i + 1 < args.size() else fallback
