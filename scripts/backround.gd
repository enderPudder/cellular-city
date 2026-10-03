extends AnimatedSprite2D

func _ready() -> void:
	if Globals.player_plant_or_animal:
		self.play("veins")
	else:
		self.play("plant leaf")
	# Connect to the window resize signal to keep it full-screen dynamically
	get_tree().root.size_changed.connect(scale_to_fullscreen)
	scale_to_fullscreen()

func scale_to_fullscreen() -> void:
	# 1. Get the current size of the game window/viewport
	var viewport_size = get_viewport().get_visible_rect().size
	
	# 2. Get the actual pixel size of the current animation frame
	var current_frame_texture = sprite_frames.get_frame_texture(animation, frame)
	if current_frame_texture == null:
		return
		
	var sprite_size = current_frame_texture.get_size()
	
	# 3. Calculate the required scale and apply it
	scale.x = viewport_size.x / sprite_size.x
	scale.y = viewport_size.y / sprite_size.y
