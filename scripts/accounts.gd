class_name AccountStore
extends RefCounted
## Server-side account + character storage in a single JSON file.
## Passwords are stored as SHA-256(salt + password) with a random per-account salt.
## (Fine for a prototype; a real game should use a slow KDF such as Argon2/bcrypt
## in a separate auth service, and a real database.)

var path: String
var data := {"version": 1, "accounts": {}}


func _init(save_path: String) -> void:
	path = save_path


func load_file() -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Could not open %s" % path)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("accounts"):
		data = parsed


func save_file() -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write %s" % tmp)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	# write to a temp file then swap, so a crash mid-write can't corrupt saves
	var dir := DirAccess.open(path.get_base_dir())
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	return dir.rename(tmp.get_file(), path.get_file()) == OK


static func key_for(account_name: String) -> String:
	return account_name.strip_edges().to_lower()


func has_account(account_name: String) -> bool:
	return data["accounts"].has(key_for(account_name))


static func hash_password(salt: String, password: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((salt + password).to_utf8_buffer())
	return ctx.finish().hex_encode()


func create_account(account_name: String, password: String) -> Dictionary:
	var salt := Crypto.new().generate_random_bytes(16).hex_encode()
	var acc := {
		"name": account_name,
		"salt": salt,
		"hash": hash_password(salt, password),
		"created": Time.get_datetime_string_from_system(true),
		"character": {},
	}
	data["accounts"][key_for(account_name)] = acc
	return acc


func check_password(account_name: String, password: String) -> bool:
	var acc: Dictionary = data["accounts"].get(key_for(account_name), {})
	if acc.is_empty():
		return false
	return hash_password(str(acc["salt"]), password) == str(acc["hash"])


func get_account(account_name: String) -> Dictionary:
	return data["accounts"].get(key_for(account_name), {})


func set_character(account_name: String, character: Dictionary) -> void:
	var acc := get_account(account_name)
	if not acc.is_empty():
		character = character.duplicate()
		if character.has("stash"):   # the stash is account-wide: stored on the account, not the character
			acc["stash"] = character["stash"]
			character.erase("stash")
		acc["character"] = character
		acc["last_saved"] = Time.get_datetime_string_from_system(true)
