extends SceneTree
## Localization tests — guard the translation pipeline (issue #3).
##
## Run with:
##   godot --headless --path . --script res://tests/i18n_tests.gd
##
## Enforces, for every shipping catalog:
##   * completeness — every msgid in locale/messages.pot has a non-empty
##     translation (a half-translated UI is the classic i18n regression);
##   * printf-specifier integrity — %d/%s/%02d/%% tokens match the source
##     one-for-one (a dropped %s crashes the `%` format call at runtime);
##   * live resolution — the .po actually imported and TranslationServer
##     returns the catalog string under that locale, falling back to the
##     English key under "en".
##
## Exits 0 on success, 1 on any failure (CI-friendly).

const POT_PATH := "res://locale/messages.pot"
const CATALOGS := [
	["es", "res://locale/es.po"],
	["fr", "res://locale/fr.po"],
	["zh_CN", "res://locale/zh_CN.po"],
	["ar", "res://locale/ar.po"],
	["hi", "res://locale/hi.po"],
]

# A handful of anchor strings asserted exactly, so a corrupted catalog (wrong
# column, mojibake, truncated import) fails loudly instead of silently.
const ANCHORS := {
	"es": {"Free-for-all": "Todos contra todos", "QUIT": "SALIR", "FUEL": "COMB."},
	"fr": {"Free-for-all": "Chacun pour soi", "QUIT": "QUITTER", "FUEL": "CARB."},
	"zh_CN": {"Free-for-all": "混战", "QUIT": "退出", "FUEL": "燃料"},
	"ar": {"Free-for-all": "الكل ضد الكل", "QUIT": "خروج", "FUEL": "الوقود"},
	"hi": {"Free-for-all": "सबके खिलाफ सब", "QUIT": "बाहर निकलें", "FUEL": "ईंधन"},
}

var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("=== XSpaceWar-AI — i18n tests ===")
	var pot := _parse_po(POT_PATH)
	_check("POT parses with entries", pot.size() > 50, "got %d" % pot.size())

	var loaded := TranslationServer.get_loaded_locales()
	for entry in CATALOGS:
		var code: String = entry[0]
		_check("%s is a loaded locale" % code, code in loaded,
			"loaded: %s" % str(loaded))

	for entry in CATALOGS:
		_test_catalog(String(entry[0]), String(entry[1]), pot)

	_test_runtime_resolution()
	_test_locale_fallback()

	print("=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _test_catalog(code: String, path: String, pot: Dictionary) -> void:
	var cat := _parse_po(path)
	# Completeness: every source msgid is answered, non-empty.
	var missing: Array[String] = []
	for key in pot:
		if not cat.has(key) or String(cat[key]).strip_edges() == "":
			missing.append(key)
	_check("%s covers every msgid (%d)" % [code, pot.size()], missing.is_empty(),
		"missing %d, e.g. %s" % [missing.size(), str(missing.slice(0, 3))])

	# Specifier integrity across the whole catalog.
	var broken: Array[String] = []
	for key in cat:
		if not _specifiers_match(key, String(cat[key])):
			broken.append("%s -> %s" % [key, cat[key]])
	_check("%s preserves every format specifier" % code, broken.is_empty(),
		str(broken.slice(0, 3)))

	# Anchors: exact values guard against corruption / wrong column.
	for src in ANCHORS.get(code, {}):
		var want: String = ANCHORS[code][src]
		_check("%s anchor '%s'" % [code, src], cat.get(src, "") == want,
			"got '%s', want '%s'" % [cat.get(src, ""), want])

func _test_runtime_resolution() -> void:
	# The compiled .translation must answer through the live server, not just
	# the source file — this is what the running game actually calls.
	for entry in CATALOGS:
		var code: String = entry[0]
		var cat := _parse_po(String(entry[1]))
		TranslationServer.set_locale(code)
		var ok := true
		var detail := ""
		for src in ANCHORS.get(code, {}):
			var got := TranslationServer.translate(src)
			if got != ANCHORS[code][src]:
				ok = false
				detail = "%s -> '%s'" % [src, got]
				break
		_check("%s resolves through TranslationServer" % code, ok, detail)

func _test_locale_fallback() -> void:
	# "en" has no catalog: every lookup falls through to the English key.
	TranslationServer.set_locale("en")
	_check("en falls through to source", TranslationServer.translate("QUIT") == "QUIT",
		"got '%s'" % TranslationServer.translate("QUIT"))
	# Switching locale changes the answer (no stale caching).
	TranslationServer.set_locale("es")
	var es_q := TranslationServer.translate("QUIT")
	TranslationServer.set_locale("fr")
	var fr_q := TranslationServer.translate("QUIT")
	_check("locale switch is live", es_q == "SALIR" and fr_q == "QUITTER",
		"es='%s' fr='%s'" % [es_q, fr_q])

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  [PASS] ", name)
	else:
		_failed += 1
		print("  [FAIL] ", name, ("  -> " + detail) if detail != "" else "")

## Minimal gettext PO reader: msgid/msgstr pairs with quoted-string
## continuation lines. Skips the header entry (msgid ""). Good enough for our
## hand-authored catalogs (no plurals, no contexts).
func _parse_po(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot open %s" % path)
		return out
	var mode := ""          # "id" | "str" | ""
	var cur_id := ""
	var cur_str := ""
	while not f.eof_reached():
		var line := f.get_line()
		var t := line.strip_edges()
		if t.begins_with("#") or t == "":
			if mode == "str" and cur_id != "":
				out[cur_id] = cur_str
			mode = ""
			cur_id = ""
			cur_str = ""
			continue
		if t.begins_with("msgid "):
			# A fresh msgid closes the previous completed pair.
			if mode == "str" and cur_id != "":
				out[cur_id] = cur_str
				cur_id = ""
				cur_str = ""
			mode = "id"
			cur_id = _po_unquote(t.substr(6))
		elif t.begins_with("msgstr "):
			mode = "str"
			cur_str = _po_unquote(t.substr(7))
		elif t.begins_with("\""):
			if mode == "id":
				cur_id += _po_unquote(t)
			elif mode == "str":
				cur_str += _po_unquote(t)
	if mode == "str" and cur_id != "":
		out[cur_id] = cur_str
	out.erase("")   # header
	return out

## Strip the surrounding quotes from a PO token and unescape \n \" \\ \t.
func _po_unquote(s: String) -> String:
	var u := s.strip_edges()
	if u.length() >= 2 and u.begins_with("\"") and u.ends_with("\""):
		u = u.substr(1, u.length() - 2)
	u = u.replace("\\n", "\n").replace("\\t", "\t")
	u = u.replace("\\\"", "\"").replace("\\\\", "\\")
	return u

## Multiset of printf specifiers in a string: %% (literal) plus %[flags]verb.
func _specifiers(s: String) -> Array:
	var re := RegEx.create_from_string("%%|%[-+ 0-9.]*[a-zA-Z]")
	var toks: Array[String] = []
	for m in re.search_all(s):
		toks.append(m.get_string())
	toks.sort()
	return toks

func _specifiers_match(src: String, dst: String) -> bool:
	return _specifiers(src) == _specifiers(dst)
