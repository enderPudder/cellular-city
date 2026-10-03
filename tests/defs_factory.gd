class_name DefsFactory extends RefCounted
## Builds OrganelleDefs in code for unit tests. Defaults come from OrganelleDef.


static func make(id: String, props: Dictionary = {}) -> OrganelleDef:
	var d := OrganelleDef.new()
	d.id = id
	d.display_name = id
	for key in props:
		d.set(key, props[key])
	return d
