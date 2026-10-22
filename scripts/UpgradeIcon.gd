class_name UpgradeIcon
extends GlyphView
## An upgrade card's icon: the glyph of the upgrade (the Launcher card follows the equipped launcher) on a plate.

var kind := "ramp"

func _init() -> void:
	plate = Style.SURFACE_DARK
	col = Style.TEXT

func set_kind(k: String) -> void:
	kind = k
	set_glyph(k)
