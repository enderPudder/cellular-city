class_name OrganelleCatalog extends RefCounted

const DIR := "res://data/organelles/"


static func load_all() -> Array[OrganelleDef]:
	var out: Array[OrganelleDef] = []
	for file_name in ResourceLoader.list_directory(DIR):
		if file_name.ends_with(".tres"):
			var def := load(DIR + file_name) as OrganelleDef
			if def != null:
				out.append(def)
	return out
