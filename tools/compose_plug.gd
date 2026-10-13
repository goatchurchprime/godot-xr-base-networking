@tool
extends SceneTree

## Small development-time project composer.
##
## A project-level plug.gd declares neighbouring repositories and the folders
## they expose beneath this project's res:// tree. Generated links are never
## committed. Use `status strict` in CI when the declared commit must match.

var _peers: Array[Dictionary] = []
var _profile := "base"


func peer(
	name: String,
	local_path: String,
	expected_commit: String,
	mounts: Array,
	profiles: Array[String] = ["base"]
) -> void:
	_peers.append({
		"name": name,
		"local_path": local_path,
		"expected_commit": expected_commit,
		"mounts": mounts,
		"profiles": profiles,
	})


func mount(source: String, target: String) -> Dictionary:
	return {"source": source, "target": target}


func _plugging() -> void:
	pass


func _initialize() -> void:
	_plugging()
	var arguments := OS.get_cmdline_args()
	var action := "status"
	for candidate in ["status", "link", "unlink"]:
		if candidate in arguments:
			action = candidate
			break
	var strict := "strict" in arguments
	for candidate in ["base", "networked"]:
		if candidate in arguments:
			_profile = candidate
			break
	var result := 0
	match action:
		"status":
			result = _status(strict)
		"link":
			result = _link_all(strict)
		"unlink":
			result = _unlink_all()
	quit(result)


func _status(strict: bool) -> int:
	var failures := 0
	print("Godot compose status for ", ProjectSettings.globalize_path("res://"))
	for definition in _peers:
		if not _peer_enabled(definition):
			continue
		var source_root := _absolute_from_project(definition.local_path)
		var revision := _git_revision(source_root)
		var expected: String = definition.expected_commit
		var revision_matches := revision == expected
		var dirty := _git_dirty(source_root)
		print("- ", definition.name, ": ", revision if not revision.is_empty() else "missing")
		if not revision_matches:
			print("  WARNING expected ", expected)
			if strict:
				failures += 1
		if dirty:
			print("  WARNING working tree has local changes")
		for mapping in definition.mounts:
			var source := source_root.path_join(mapping.source).simplify_path()
			var target := _absolute_from_project(mapping.target)
			var state := "linked" if _link_points_to(target, source) else ("occupied" if _path_exists(target) else "missing")
			print("  ", mapping.target, " <- ", source, " [", state, "]")
	return failures


func _link_all(strict: bool) -> int:
	var failures := _status(strict)
	if failures != 0:
		print("Strict revision checks failed; no links were changed.")
		return failures
	for definition in _peers:
		if not _peer_enabled(definition):
			continue
		var source_root := _absolute_from_project(definition.local_path)
		if _git_revision(source_root).is_empty():
			push_error("Peer repository is unavailable: " + source_root)
			failures += 1
			continue
		for mapping in definition.mounts:
			var source := source_root.path_join(mapping.source).simplify_path()
			var target := _absolute_from_project(mapping.target)
			if not _path_exists(source):
				push_error("Mount source does not exist: " + source)
				failures += 1
				continue
			if _link_points_to(target, source):
				continue
			if _path_exists(target):
				push_error("Refusing to replace existing path: " + target)
				failures += 1
				continue
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			if _create_directory_link(source, target) != OK:
				failures += 1
			else:
				print("Linked ", mapping.target, " -> ", source)
	return failures


func _unlink_all() -> int:
	var failures := 0
	for definition in _peers:
		if not _peer_enabled(definition):
			continue
		var source_root := _absolute_from_project(definition.local_path)
		for mapping in definition.mounts:
			var source := source_root.path_join(mapping.source).simplify_path()
			var target := _absolute_from_project(mapping.target)
			if not _path_exists(target):
				continue
			if not _link_points_to(target, source):
				push_error("Refusing to remove non-matching path: " + target)
				failures += 1
				continue
			if DirAccess.remove_absolute(target) != OK:
				push_error("Could not remove generated link: " + target)
				failures += 1
			else:
				print("Unlinked ", mapping.target)
	return failures


func _peer_enabled(definition: Dictionary) -> bool:
	var profiles: Array = definition.profiles
	return "base" in profiles or _profile in profiles


func _absolute_from_project(path: String) -> String:
	if path.is_absolute_path():
		return path.simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()


func _path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


func _git_revision(repository: String) -> String:
	var result := _run("git", ["-C", repository, "rev-parse", "HEAD"])
	return result.output.strip_edges() if result.code == 0 else ""


func _git_dirty(repository: String) -> bool:
	var result := _run("git", ["-C", repository, "status", "--porcelain"])
	return result.code == 0 and not result.output.strip_edges().is_empty()


func _resolved_path(path: String) -> String:
	if OS.get_name() == "Windows":
		var script := "(Get-Item -LiteralPath '" + path.replace("'", "''") + "').Target"
		var result := _run("powershell", ["-NoProfile", "-Command", script])
		return result.output.strip_edges() if result.code == 0 else ""
	var result := _run("readlink", ["-f", path])
	return result.output.strip_edges() if result.code == 0 else ""


func _link_points_to(target: String, source: String) -> bool:
	if not _path_exists(target):
		return false
	return _resolved_path(target) == _resolved_path(source)


func _create_directory_link(source: String, target: String) -> int:
	if OS.get_name() == "Windows":
		var result := _run("cmd", ["/C", "mklink", "/J", target, source])
		if result.code != 0:
			push_error(result.output)
		return result.code
	var result := _run("ln", ["-s", source, target])
	if result.code != 0:
		push_error(result.output)
	return result.code


func _run(program: String, arguments: Array) -> Dictionary:
	var output: Array = []
	var code := OS.execute(program, PackedStringArray(arguments), output, true)
	return {"code": code, "output": "\n".join(output)}
