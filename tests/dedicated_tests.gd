extends SceneTree
## Tests for the DEDICATED SERVER moderation console (issue #4): command parsing
## (kick / ban / unban / bans / players / watch), --ban / comma-list seeding, and
## the --banfile persistence store (round-trips console bans across a restart).
##
## net_tests.gd already exercises kick/ban over live peers; this pins the console
## layer in server/dedicated_main.gd — the parsing and the file-backed ban store
## that were previously only covered by hand-running the server.
##
## Run with:
##   godot --headless --path . --script res://tests/dedicated_tests.gd

const DEDICATED := preload("res://server/dedicated_main.gd")
const BANFILE := "user://test_dedicated_bans.txt"

var _passed := 0
var _failed := 0
var _d = null   ## one reused dedicated-server instance (a SceneTree — reused so
                ## the suite leaks a single viewport RID at exit, not one per case)

func _initialize() -> void:
	print("=== XSpaceWar-AI — dedicated moderation console tests ===")
	_d = DEDICATED.new()
	_test_seed_ban_lists()
	_test_console_ban_unban()
	_test_command_robustness()
	_test_name_filtering()
	_test_banfile_persistence()
	_test_banfile_comments()
	_cleanup()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  [PASS] ", name)
	else:
		_failed += 1
		print("  [FAIL] ", name, ("  -> " + detail) if detail != "" else "")

## A fresh dedicated-server instance wired to an un-opened host (the ban store is
## pure dict/file state — no transport needed to drive the console).
## Reset the shared instance to a clean, un-opened host (each case starts fresh).
func _fresh(banfile := ""):
	_d.host = NetHost.new(GameSession.new())
	_d._banfile = banfile
	return _d

func _has(host, name: String) -> bool:
	return host.ban_list().has(name.to_upper())

# --------------------------------------------------------------------------

## --ban accepts repeats AND comma-separated lists; --banfile seeds one per line.
func _test_seed_ban_lists() -> void:
	var d = _fresh()
	d._seed_bans(["Alpha,Bravo", "Charlie"], "")
	_check("seed: comma-list + repeat all banned",
		_has(d.host, "Alpha") and _has(d.host, "Bravo") and _has(d.host, "Charlie"),
		"list=%s" % str(d.host.ban_list()))
	_check("seed: exactly three names", d.host.ban_list().size() == 3,
		"size=%d" % d.host.ban_list().size())

## `ban`/`unban` mutate the store; matching is case-insensitive; re-ban dedupes.
func _test_console_ban_unban() -> void:
	var d = _fresh()
	d._run_command("ban Delta")
	_check("console: `ban Delta` adds to store", _has(d.host, "Delta"))
	d._run_command("ban delta")
	_check("console: re-ban (diff case) dedupes", d.host.ban_list().size() == 1,
		"size=%d" % d.host.ban_list().size())
	d._run_command("/ban Echo")            # leading slash is stripped
	_check("console: leading `/` accepted", _has(d.host, "Echo"))
	d._run_command("unban DELTA")          # case-insensitive removal
	_check("console: `unban` (diff case) removes", not _has(d.host, "Delta"))
	_check("console: unban left Echo intact", _has(d.host, "Echo"))

## Every command tolerates an empty/peerless server without crashing, and
## unknown/blank input is handled.
func _test_command_robustness() -> void:
	var d = _fresh()
	d._run_command("ban Griefer")
	d._run_command("kick Nobody")          # no connected peers -> removes 0
	_check("robust: kick of an absent name doesn't ban", _has(d.host, "Nobody") == false)
	_check("robust: kick left existing bans intact", _has(d.host, "Griefer"))
	# These print status against an empty host; assert only that they don't throw.
	d._run_command("players")
	d._run_command("watch")
	d._run_command("bans")
	d._run_command("help")
	d._run_command("frobnicate")           # unknown
	d._run_command("")                      # blank
	d._run_command("ban")                   # missing arg -> usage, no change
	_check("robust: `ban` with no arg is a no-op", d.host.ban_list().size() == 1,
		"size=%d" % d.host.ban_list().size())

## Bans run through NetProtocol.filter_name, so junk chars are stripped before
## storage (a ban must match the sanitized join name to bite).
func _test_name_filtering() -> void:
	var d = _fresh()
	d._run_command("ban gr@ie#f")
	_check("filter: junk chars stripped in stored ban", _has(d.host, "GRIEF"),
		"list=%s" % str(d.host.ban_list()))

## The banfile is the persistence store: console bans are rewritten to it and a
## fresh server seeded from that file inherits them (survives a restart).
func _test_banfile_persistence() -> void:
	_rm(BANFILE)
	var d = _fresh(BANFILE)
	d._run_command("ban Foxtrot")          # ban -> _persist_bans() writes the file
	d._run_command("ban Golf")
	d._run_command("unban Foxtrot")        # unban also rewrites
	_check("persist: banfile was written", FileAccess.file_exists(BANFILE))
	# Simulate a restart: a brand-new server seeded from the same file.
	var d2 = _fresh(BANFILE)
	d2._seed_bans([], BANFILE)
	_check("persist: restart inherits Golf", _has(d2.host, "Golf"))
	_check("persist: restart drops unbanned Foxtrot", not _has(d2.host, "Foxtrot"),
		"list=%s" % str(d2.host.ban_list()))

## _seed_bans skips blank lines and `#` comments in the banfile.
func _test_banfile_comments() -> void:
	_rm(BANFILE)
	var f := FileAccess.open(BANFILE, FileAccess.WRITE)
	f.store_line("# a comment line")
	f.store_line("")
	f.store_line("Hotel")
	f.close()
	var d = _fresh(BANFILE)
	d._seed_bans([], BANFILE)
	_check("comments: real name loaded", _has(d.host, "Hotel"))
	_check("comments: comment/blank not banned", d.host.ban_list().size() == 1,
		"list=%s" % str(d.host.ban_list()))

func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _cleanup() -> void:
	_rm(BANFILE)
