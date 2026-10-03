class_name OrganelleTip extends RefCounted
## Short hover text for an organelle button: what it is, what it must be
## connected to, and what connects to it. The long teaching text lives in the
## unlock card and the encyclopedia.


static func first_sentence(text: String) -> String:
	var i := text.find(". ")
	return text if i == -1 else text.substr(0, i + 1)


## What this organelle must be connected to (or touch) to work.
static func connect_to(def: OrganelleDef, cell_type: int) -> Array[String]:
	var out: Array[String] = []
	if def.needs_energy_link:
		out.append("a mitochondria (energy)")
	if def.needs_water_link:
		out.append("a membrane (water)" if cell_type == OrganelleDef.CellType.ANIMAL else "a membrane or cell wall (water)")
	if def.requires_adjacent != "":
		out.append("touch its %s" % def.requires_adjacent)
	if def.energy_output > 0.0:
		out.append("optional: an ER touching it, to burn fat")
	if def.protein_output > 0.0:
		out.append("a golgi apparatus (to send proteins)")
	return out


## What should be connected to this organelle.
static func connect_into(def: OrganelleDef) -> Array[String]:
	var out: Array[String] = []
	if def.max_load > 0.0:
		out.append("organelles that need energy (up to %d/s)" % int(def.max_load))
	if def.water_output > 0.0:
		out.append("organelles that need water")
	if def.fat_access:
		out.append("a mitochondria touching it (to burn fat)")
	if def.protein_capacity > 0.0:
		out.append("an ER (it sends proteins)")
	return out


## `progress` is CellSim.unlock_progress(): {meter: [current, required]}; pass it
## for a locked organelle to append its unlock requirement.
static func build(def: OrganelleDef, cell_type: int, progress: Dictionary = {}) -> String:
	var lines: Array[String] = []
	lines.append("[b]%s[/b] - %s" % [def.display_name, def.city_name])
	lines.append(first_sentence(def.function_text))
	var to := connect_to(def, cell_type)
	var into := connect_into(def)
	if to.is_empty() and into.is_empty():
		lines.append("Needs no connections.")
	if not to.is_empty():
		lines.append("[b]Connect it to:[/b]")
		for t in to:
			lines.append("- " + t)
	if not into.is_empty():
		lines.append("[b]Connect to it:[/b]")
		for t in into:
			lines.append("- " + t)
	if not progress.is_empty():
		var needs: Array[String] = []
		for meter in progress:
			needs.append("%s %d (now %d)" % [meter, progress[meter][1], progress[meter][0]])
		lines.append("[b]Locked:[/b] reach " + ", ".join(needs))
	return "\n".join(lines)
