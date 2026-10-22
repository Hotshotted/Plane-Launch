extends SceneTree
## Renders the app icon (icon.svg) to the PNG sizes the web / PWA export wants, and the boot splash (assets/splash.svg),
## which places icons/icon-512.png on the navy page: run twice (the first run makes the icons, the second the splash).
##   godot --headless --path . --script tools/make_icons.gd

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://icons")
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	for px in [144, 180, 512]:
		var img := Image.new()
		img.load_svg_from_string(svg, float(px) / 512.0)
		img.save_png("res://icons/icon-%d.png" % px)
		print("icon ", px, " ", img.get_size())
	# the splash, composed here (an SVG <image> reference would not resolve from a string): navy page, icon, propeller
	var sp := Image.create(720, 1280, false, Image.FORMAT_RGBA8)
	sp.fill(Color("14213d"))      # the brand navy: the same as the boot splash colour and the web loading page, no seam
	var icon := Image.new()
	icon.load_svg_from_string(svg, 0.62)
	sp.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), Vector2i(360 - icon.get_width() / 2, 520 - icon.get_height() / 2))
	var prop := Image.new()
	prop.load_svg_from_string("<svg xmlns='http://www.w3.org/2000/svg' width='200' height='200' viewBox='-100 -100 200 200'><g fill='#ffffff' fill-opacity='0.9'><path id='b' d='M-17 -14 L-30 -62 L-6 -97 L24 -72 L17 -14 Z'/><use href='#b' transform='rotate(120)'/><use href='#b' transform='rotate(240)'/><circle r='27'/></g><circle r='14' fill='#ffc933'/></svg>", 0.62)
	sp.blend_rect(prop, Rect2i(Vector2i.ZERO, prop.get_size()), Vector2i(360 - prop.get_width() / 2, 960 - prop.get_height() / 2))
	sp.save_png("res://assets/splash.png")
	print("splash ", sp.get_size())
	quit()
