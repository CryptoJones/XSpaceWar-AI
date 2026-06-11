extends SceneTree
## Headless tests for the procedural audio synthesis (SoundForge).
##
## Run with:
##   godot --headless --path . --script res://tests/audio_tests.gd

var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("=== XSpaceWar-AI — audio tests ===")

	var fire := SoundForge.fire()
	var boom := SoundForge.explosion()
	var hyper := SoundForge.hyperspace()
	var thrust := SoundForge.thrust_loop()

	for pair in [["fire", fire], ["explosion", boom], ["hyperspace", hyper], ["thrust", thrust]]:
		var wav: AudioStreamWAV = pair[1]
		_check("%s: synthesized non-trivial PCM" % pair[0],
			wav != null and wav.data.size() > 2000 and wav.mix_rate == SoundForge.RATE,
			"bytes=%d" % (wav.data.size() if wav != null else -1))

	_check("explosion outlasts fire", boom.data.size() > fire.data.size())
	_check("synthesis is deterministic", SoundForge.fire().data == fire.data)
	_check("thrust loops cleanly", thrust.loop_mode == AudioStreamWAV.LOOP_FORWARD
		and thrust.loop_end == thrust.data.size() / 2)

	var ambient := SoundForge.ambient_loop()
	_check("ambient: 16s looping drone synthesized",
		ambient.data.size() == int(16.0 * SoundForge.RATE) * 2
		and ambient.loop_mode == AudioStreamWAV.LOOP_FORWARD)

	# Not silence and not clipping garbage: peak in a sane range.
	var peak := 0
	for i in range(0, boom.data.size(), 2):
		peak = maxi(peak, absi(boom.data.decode_s16(i)))
	_check("explosion has audible, non-clipped peak", peak > 8000 and peak <= 32767,
		"peak=%d" % peak)

	print("=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  [PASS] ", name)
	else:
		_failed += 1
		print("  [FAIL] ", name, ("  -> " + detail) if detail != "" else "")
