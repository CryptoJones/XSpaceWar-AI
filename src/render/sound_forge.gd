class_name SoundForge
extends RefCounted
## Procedural sound synthesis — every effect is rendered to PCM at load time
## from math + seeded noise (no audio assets, per the project rule), returned
## as AudioStreamWAV (16-bit mono). Each generator is deterministic; variety
## comes from pitch_scale at playback.

const RATE := 22050

## Laser pew: falling sweep with a bright noise spit on the attack.
static func fire() -> AudioStreamWAV:
	var n := int(0.14 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	var phase := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var k := float(i) / float(n)
		var f := lerpf(1500.0, 280.0, pow(k, 0.45))
		phase += TAU * f / RATE
		var v := sin(phase) + 0.35 * sin(phase * 2.0)
		v += (rng.randf() * 2.0 - 1.0) * 0.5 * exp(-t * 90.0)
		s[i] = v * 0.8 * exp(-t * 22.0)
	return _to_wav(s)

## Explosion: lowpass-swept noise rumble with a sub-bass thump, soft-clipped.
static func explosion() -> AudioStreamWAV:
	var n := int(0.9 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 202
	var lp := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var k := float(i) / float(n)
		var cutoff := lerpf(2600.0, 140.0, pow(k, 0.5))
		var a := 1.0 - exp(-TAU * cutoff / RATE)
		lp += ((rng.randf() * 2.0 - 1.0) - lp) * a
		var v := lp * 1.6 * exp(-t * 4.2)
		v += 0.5 * sin(TAU * 55.0 * t) * exp(-t * 7.0)
		s[i] = v / (1.0 + absf(v))
	return _to_wav(s)

## Hyperspace: rising shimmer sweep that thins out as it climbs.
static func hyperspace() -> AudioStreamWAV:
	var n := int(0.55 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var k := float(i) / float(n)
		var f := lerpf(180.0, 1900.0, pow(k, 1.4))
		phase += TAU * f / RATE
		var v := sin(phase) + 0.4 * sin(phase * 1.5) + 0.2 * sin(phase * 3.01) * k
		v *= 0.7 * exp(-t * 3.0) + 0.3
		v *= minf(1.0, (1.0 - k) * 8.0)  # hard fade at the tail
		s[i] = v * 0.6
	return _to_wav(s)

## Engine rumble: leaky-integrated (brown) noise + low wobble, seam-crossfaded
## so it loops cleanly. Played as a held loop while a ship thrusts.
static func thrust_loop() -> AudioStreamWAV:
	var n := int(0.6 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var b := 0.0
	for i in range(n):
		var t := float(i) / RATE
		b += (rng.randf() * 2.0 - 1.0) * 0.18
		b *= 0.985
		s[i] = b * 2.2 + 0.12 * sin(TAU * 70.0 * t)
	var fade := int(0.05 * RATE)
	for j in range(fade):
		var w := float(j) / float(fade)
		s[n - fade + j] = s[n - fade + j] * (1.0 - w) + s[j] * w
	var peak := 0.0001
	for i in range(n):
		peak = maxf(peak, absf(s[i]))
	for i in range(n):
		s[i] = s[i] / peak * 0.7
	return _to_wav(s, true)

static func _to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
