extends Node2D
## Placeholder boot scene: shows the build stamp. The game replaces this.

func _ready() -> void:
	var l := Label.new()
	l.text = "Junkyard Launch\n%s  %s" % [BuildInfo.COMMIT, BuildInfo.TIME]
	l.add_theme_font_size_override("font_size", 48)
	l.position = Vector2(60, 200)
	add_child(l)
