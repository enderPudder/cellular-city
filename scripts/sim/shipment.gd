class_name Shipment extends RefCounted
## A vesicle of proteins travelling from a golgi to a target organelle.
## `effect` is the target's OrganelleDef.protein_effect.

var id: int = 0
var from_uid: int = 0
var to_uid: int = 0
var proteins: float = 0.0
var effect: String = ""


static func make(p_id: int, p_from: int, p_to: int, p_proteins: float, p_effect: String) -> Shipment:
	var s := Shipment.new()
	s.id = p_id
	s.from_uid = p_from
	s.to_uid = p_to
	s.proteins = p_proteins
	s.effect = p_effect
	return s
