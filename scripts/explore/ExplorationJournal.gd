class_name ExplorationJournal
extends RefCounted
## Exploration has a separate versioned save; combat progress is never rewritten here.
const SAVE_PATH := "user://exploration_v2.json"
var data: Dictionary = {"version":1,"planets":{},"biomes":{},"geology":{},"signals":{},"photographs":[],"missions":{}}
var storage_path := SAVE_PATH
var persistent := true
var last_error := OK

func _init(allow_persistence := true,path := SAVE_PATH) -> void:
	persistent=allow_persistence; storage_path=path
	if not persistent or not FileAccess.file_exists(path): return
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("version",0))!=1: return
	for key in data:
		if parsed.has(key) and typeof(parsed[key])==typeof(data[key]): data[key]=parsed[key]

func record(category: String,id: String,title: String,details: String="") -> bool:
	if not data.has(category) or not data[category] is Dictionary: return false
	if data[category].has(id): return false
	data[category][id]={"title":title,"details":details,"time":Time.get_datetime_string_from_system()}
	flush()
	return true

func photograph(path: String,planet: String,biome: String) -> void:
	data.photographs.append({"path":path,"planet":planet,"biome":biome,"time":Time.get_datetime_string_from_system()})
	# Bound the metadata list; existing photograph files are never deleted.
	if data.photographs.size()>256: data.photographs.pop_front()
	flush()

func flush() -> void:
	if not persistent: return
	var file := FileAccess.open(storage_path+".tmp",FileAccess.WRITE)
	if file==null: last_error=FileAccess.get_open_error(); return
	file.store_string(JSON.stringify(data,"\t")); file.close()
	last_error=DirAccess.rename_absolute(storage_path+".tmp",storage_path)

func describe() -> String:
	var lines: PackedStringArray=[]
	for category in ["planets","biomes","geology","signals","missions"]:
		lines.append(category.to_upper()+"  /  "+str(data[category].size()))
		for entry in data[category].values():
			lines.append("  "+str(entry.title)+"  ·  "+str(entry.details))
		lines.append("")
	lines.append("PHOTOGRAPHS  /  "+str(data.photographs.size()))
	return "\n".join(lines)
