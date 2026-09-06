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
## Wrap slingshot: a quick rising doppler zip.
static func wrap_zip() -> AudioStreamWAV:
	var n := int(RATE * 0.28)
	var data := PackedFloat32Array()
	data.resize(n)
	for i in range(n):
		var t := float(i) / float(RATE)
		var k := float(i) / float(n)
		var f := lerpf(220.0, 1400.0, k * k)
		var env := (1.0 - k) * minf(1.0, k * 14.0)
		data[i] = sin(TAU * f * t) * 0.5 * env \
			+ sin(TAU * f * 2.01 * t) * 0.18 * env
	return _to_wav(data)

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

## Ambient space drone: detuned low sines beating slowly against each other,
## a drifting fifth, and a filtered-noise air swell — 16 seconds, seam-
## crossfaded to loop forever. Played quietly under everything.
static func ambient_loop() -> AudioStreamWAV:
	var n := int(16.0 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var lp := 0.0
	var a_noise := 1.0 - exp(-TAU * 240.0 / RATE)
	for i in range(n):
		var t := float(i) / RATE
		var v := 0.30 * sin(TAU * 55.0 * t)
		v += 0.22 * sin(TAU * 55.17 * t)                       # beats vs the root
		v += 0.16 * sin(TAU * 82.41 * t + 0.4 * sin(TAU * 0.07 * t))
		v += 0.12 * sin(TAU * 110.0 * t) * (0.6 + 0.4 * sin(TAU * 0.05 * t))
		lp += ((rng.randf() * 2.0 - 1.0) - lp) * a_noise
		v += lp * 0.10 * (0.5 + 0.5 * sin(TAU * 0.09 * t + 2.0))
		s[i] = v * 0.6
	var fade := int(1.0 * RATE)
	for j in range(fade):
		var w := float(j) / float(fade)
		s[n - fade + j] = s[n - fade + j] * (1.0 - w) + s[j] * w
	var peak := 0.0001
	for i in range(n):
		peak = maxf(peak, absf(s[i]))
	for i in range(n):
		s[i] = s[i] / peak * 0.55
	return _to_wav(s, true)

## Match-won fanfare: a quick rising four-note arpeggio with a soft tail.
static func fanfare() -> AudioStreamWAV:
	var notes := [392.0, 523.25, 659.25, 783.99]  # G4 C5 E5 G5
	var step := 0.16
	var n := int((step * notes.size() + 0.5) * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var v := 0.0
		for k in range(notes.size()):
			var t0 := t - step * float(k)
			if t0 < 0.0:
				continue
			var f: float = notes[k]
			var env := exp(-t0 * (3.0 if k == notes.size() - 1 else 9.0))
			v += (sin(TAU * f * t0) + 0.3 * sin(TAU * f * 2.0 * t0)) * env
		s[i] = v * 0.35
	return _to_wav(s)

## Shield deflection: bright electric crackle with resonant punch.
static func shield_hit() -> AudioStreamWAV:
	var n := int(0.18 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var phase := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var k := float(i) / float(n)
		var f := lerpf(920.0, 160.0, pow(k, 0.4))
		phase += TAU * f / RATE
		var v := sin(phase) + 0.45 * sin(phase * 2.4)
		v += (rng.randf() * 2.0 - 1.0) * 0.45 * exp(-t * 35.0)
		s[i] = v * 0.75 * exp(-t * 14.0)
	return _to_wav(s)

## Hit confirmation: high, crisp dual-tone chirp when landing a shot.
static func hit_confirm() -> AudioStreamWAV:
	var n := int(0.09 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var v := 0.5 * sin(TAU * 1760.0 * t) + 0.4 * sin(TAU * 2637.0 * t)
		s[i] = v * exp(-t * 38.0) * 0.7
	return _to_wav(s)

## Threat warning: rapid double pulse blip when hostile ordnance is closing fast.
static func threat_warning() -> AudioStreamWAV:
	var n := int(0.12 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var pulse := 1.0 if (t < 0.04 or (t > 0.06 and t < 0.10)) else 0.1
		var v := sin(TAU * 1200.0 * t) * pulse
		s[i] = v * 0.5
	return _to_wav(s)

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
