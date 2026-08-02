extends Node3D
## Deterministic check that FX.spark_burst actually puts pixels on screen.
## Emits a burst at a fixed point in front of a fixed camera and screenshots it.
func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 6)
	cam.current = true
	add_child(cam)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.04)
	env.environment = e
	add_child(env)
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().process_frame
	for i in 6:
		FX.spark_burst(self, Vector3(0, 0, 0), Vector3.UP, 24,
			Color(1.0, 0.68, 0.26), 4.0, 14.0, 0.25, 0.6, 180.0)
	# let them fly a little so they are not all stacked on the origin
	for i in 12:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir + "/spark_probe.png")
	# count non-black pixels as the actual assertion
	var lit := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			if img.get_pixel(x, y).get_luminance() > 0.08:
				lit += 1
	print("[SPARK] lit_samples=%d" % lit)
	get_tree().quit()
