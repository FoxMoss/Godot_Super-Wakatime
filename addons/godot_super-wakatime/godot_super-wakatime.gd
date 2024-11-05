@tool
extends EditorPlugin


# Utilities
const Utils = preload("res://addons/godot_super-wakatime/utils.gd").new()
const DecompressorUtils = preload("res://addons/godot_super-wakatime/decompressor.gd").new()

# Hearbeat class
const HeartBeat = preload("res://addons/godot_super-wakatime/heartbeat.gd")
var last_heartbeat = HeartBeat.new()

# Paths, Urls
const PLUGIN_PATH: String = "res://addons/godot_super-wakatime"
const ZIP_PATH: String = "%s/wakatime.zip" % PLUGIN_PATH

const WAKATIME_URL_FMT: String = "https://github.com/wakatime/wakatime-cli/releases/download/v1.54.0/{wakatime_build}.zip"
const DECOMPERSSOR_URL_FMT: String = "https://github.com/ouch-org/ouch/releases/download/0.3.1/{ouch_build}"

# Names for menu
const API_MENU_ITEM: String = "Wakatime API key"
const CONFIG_MENU_ITEM: String = "Wakatime Config File"

# Directories to grab wakatime from
var wakatime_dir = null
var wakatime_cli = null
var decompressor_cli = null

const ApiKeyPrompt: PackedScene = preload("res://addons/godot_super-wakatime/api_key_prompt.tscn")

# Set platform
var system_platform: String = Utils.set_platform()[0]
var system_architecture: String = Utils.set_platform()[1]

var debug: bool = false


func _ready() -> void:
	setup_plugin()
	
func _exit_tree() -> void:
	_disable_plugin()

func setup_plugin() -> void:
	"""Setup Wakatime plugin, download dependencies if needed, initialize menu"""
	Utils.plugin_print("Setting up %s" % get_user_agent())
	check_dependencies()
	
	# Grab API key if needed
	var api_key = api_key()
	if api_key == null:
		request_api_key()
	await get_tree().process_frame
	
	# Add menu buttons
	add_tool_menu_item(API_MENU_ITEM, request_api_key)
	add_tool_menu_item(CONFIG_MENU_ITEM, open_config)
	
	# Connect editor and playground signals
	var script_editor: ScriptEditor = get_editor_interface().get_script_editor()
	script_editor.call_deferred("connect", "editor_script_changed", Callable(self, "_on_editor_script_changed"))

func _disable_plugin() -> void:
	remove_tool_menu_item(API_MENU_ITEM)
	remove_tool_menu_item(CONFIG_MENU_ITEM)
	
	var script_editor: ScriptEditor = get_editor_interface().get_script_editor()
	if script_editor.is_connected("editor_script_changed", Callable(self, "_on_editor_script_changed")):
		script_editor.disconnect("editor_script_changed", Callable(self, "_on_editor_script_changed"))

func open_config():
	"""Open wakatime config file"""
	OS.shell_open(Utils.config_filepath(system_platform, PLUGIN_PATH))
	
func get_waka_dir() -> String:
	"""Search for and return wakatime directory"""
	if wakatime_dir == null:
		wakatime_dir = "%s/.wakatime" % Utils.home_directory(system_platform, PLUGIN_PATH)
	return wakatime_dir
	
func get_waka_cli() -> String:
	"""Get wakatime_cli file"""
	if wakatime_cli == null:
		var build = Utils.get_waka_build
		var ext: String = ".exe" if system_platform == "windows" else ''
		wakatime_cli = "%s/%s%s" % [get_waka_dir(), build, ext]
	return wakatime_cli
	
func check_dependencies() -> void:
	"""Make sure all dependencies exist"""
	if !Utils.wakatime_cli_exists(wakatime_cli):
		download_wakatime()
	if !DecompressorUtils.lib_exists(decompressor_cli, system_platform, PLUGIN_PATH):
		download_decompressor()
	
func download_wakatime() -> void:
	"""Download wakatime cli"""
	Utils.plugin_print("Downloading Wakatime CLI...")
	var url: String = WAKATIME_URL_FMT.format({"wakatime_build": Utils.get_waka_build(system_platform, system_architecture)})
	
	# Try downloading wakatime
	var http = HTTPRequest.new()
	http.download_file = ZIP_PATH
	http.connect("request_completed", Callable(self, "_wakatime_download_completed"))
	add_child(http)
	
	# Handle errors
	var status = http.request(url)
	if status != OK:
		Utils.plugin_print_err("Failed to start downloading Wakatime [Error: %s]" % status)
		_disable_plugin()
	
func download_decompressor() -> void:
	"""Download ouch decompressor"""
	Utils.plugin_print("Downloading Ouch! decompression library...")
	var url: String = DECOMPERSSOR_URL_FMT.format({"ouch_build": Utils.get_ouch_build()})
	if system_platform == "windows":
		url += ".exe"
		
	# Try to download ouch
	var http = HTTPRequest.new()
	http.download_file = DecompressorUtils.decompressor_cli()
	http.connect("request_completed", Callable(self, "_decompressor_download_finished"))
	add_child(http)
	
	# Handle errors
	var status = http.request(url)
	if status != OK:
		_disable_plugin()
		Utils.plugin_print_err("Failed to start downloading Ouch! library [Error: %s]" % status)
		
func _wakatime_download_finished(result, status, headers, body) -> void:
	"""Finish downloading wakatime, handle errors"""
	if result != HTTPRequest.RESULT_SUCCESS:
		Utils.plugin_print_err("Error while downloading Wakatime CLI")
		_disable_plugin()
		return
	
	Utils.plugin_print("Wakatime CLI has been installed succesfully! Located at %s" % ZIP_PATH)
	extract_files(ZIP_PATH, get_waka_dir())
	
func _decompressor_download_finished(result, status, headers, body) -> void:
	"""Handle errors and finishi decompressor download"""
	# Error while downloading
	if result != HTTPRequest.RESULT_SUCCESS:
		Utils.plugin_print_err("Error while downloading Ouch! library")
		_disable_plugin()
		return
	
	# Error while saving
	if !DecompressorUtils.lib_exists(decompressor_cli, system_platform, PLUGIN_PATH):
		Utils.plugin_print_err("Failed to save Ouch! library")
		_disable_plugin()
		return
		
	# Save decompressor path, give write permissions to it
	var decompressor: String = ProjectSettings.globalize_path(DecompressorUtils.decompressor_cli(decompressor_cli, system_platform, PLUGIN_PATH))
	if system_platform == "linux" or system_platform == "darwin":
		OS.execute("chmod", ["+x", decompressor], [], true)
		
	# Extract files, allowing usage of Ouch!
	Utils.plugin_print("Ouch! has been installed succesfully! Located at %s" % DecompressorUtils.decompressor_cli(decompressor_cli, system_platform, PLUGIN_PATH))
	extract_files(ZIP_PATH, get_waka_dir())
	
func extract_files(source: String, destination: String) -> void:
	"""Extract downloaded Wakatime zip"""
	# If decompression library and wakatime zip folder don't exist, return
	if not (DecompressorUtils.lib_exists(decompressor_cli, system_platform, PLUGIN_PATH) and Utils.wakatime_zip_exists(ZIP_PATH)):
		return
		
	# Get paths as global
	Utils.plugin_print("Extracting Wakatime...")
	var decompressor: String = ProjectSettings.globalize_path(DecompressorUtils.decompressor_cli(decompressor_cli, system_platform, system_architecture))
	var src: String = ProjectSettings.globalize_path(source)
	var dest: String = ProjectSettings.globalize_path(destination)
	
	# Execute Ouch! decompression command, catch errors
	var errors: Array[Variant] = []
	var args: Array[String] = ["--yes", "decompress", src, "--dir", dest]
	var error: int = OS.execute(decompressor, args, errors, true)
	if error:
		Utils.plugin_print(errors)
		_disable_plugin()
		return
		
	# Results
	if Utils.wakatime_cli_exists(wakatime_cli):
		Utils.plugin_print("Wakatime CLI installed (path: %s)" % get_waka_cli())
	else:
		_disable_plugin()
		Utils.plugin_print_err("Installation of Wakatime failed")
		
	# Remove leftover files
	clean_files()
	
func clean_files():
	"""Delete files that aren't needed anymore"""
	if Utils.wakatime_zip_exists(ZIP_PATH):
		delete_file(ZIP_PATH)
	if DecompressorUtils.lib_exists(decompressor_cli, system_platform, PLUGIN_PATH):
		delete_file(ZIP_PATH)
		
func delete_file(path: String) -> void:
	"""Delete file at specified path"""
	var dir: DirAccess = DirAccess.open("res://")
	var status: int = dir.remove(path)
	if status != OK:
		Utils.plugin_print_err("Failed to clean unnecesary file at %s" % path)
	else:
		Utils.plugin_print("Clean unncecesary file at %s" % path)

func api_key() -> String:
	"""Get wakatime api key"""
	var result: Array[Variant] = []
	# Handle errors while getting the key
	var err: int = OS.execute(get_waka_cli(), ["--config-read", "api_key"])
	if err == -1:
		return null
		
	# Trim API key from whitespaces and return it
	var key = result[0].strip_edges()
	if key.is_empty():
		return null
	return key
	
func request_api_key() -> void:
	"""Request Wakatime API key from the user"""
	# Prepare prompt
	var prompt: Node = ApiKeyPrompt.instantiate()
	_set_api_key(prompt, api_key())
	_register_api_key_signals(prompt)
	
	# Show prompt and hide it on request
	add_child(prompt)
	prompt.popup_centered()
	await prompt.popup_hide
	prompt.queue_free()
	
func _set_api_key(prompt: PopupPanel, api_key: String) -> void:
	"""Set API key from prompt"""
	# Safeguard against empty key
	if api_key == null:
		api_key = ''
		
	# Set correct text, to show API key
	var edit_field: Node = prompt.get_node("vbox_container/hbox_container_top/line_edit")
	edit_field.text = api_key
	
func _register_api_key_signals(prompt: PopupPanel) -> void:
	"""Connect all signals related to API key popup"""
	# Get all Nodes
	var show_button: Node = prompt.get_node("vbox_container/hbox_container_top/show_btn")
	var save_button: Node = prompt.get_node("vbox_container/hbox_container_bottom/save_btn")
	
	# Connect them to press events
	show_button.connect("pressed", Callable(self, "_on_toggle_key_text").bind(prompt))
	save_button.connect("pressed", Callable(self, "_on_save_key").bind(prompt))
	prompt.connect("popup_hide", Callable(self, "_on_popup_hide").bind(prompt))
	
func _on_popup_hide(prompt: PopupPanel):
	"""Close the popup window when user wants to hide it"""
	prompt.queue_free()
	
func _on_toogle_key_text(prompt: PopupPanel) -> void:
	"""Handle hiding and showing API key"""
	# Get nodes
	var show_button: Node = prompt.get_node("vbox_container/hbox_container_top/show_btn")
	var edit_field: Node = prompt.get_node("vbox_container/hbox_container_top/line_edit")
	
	# Set the correct text and hide field if needed
	edit_field.secret = not edit_field.secret
	show_button.text = "Show" if edit_field.secret else "Hide"
	
func _on_save_key(prompt: PopupPanel) -> void:
	"""Handle entering API key"""
	# Get text field node and api key that's entered
	var edit_field: Node = prompt.get_node("vbox_container/hbox_container_top/line_edit")
	var api_key  = edit_field.text.strip_edges()
	
	# Try to set api key for wakatime and handle errors
	var err: int = OS.execute(get_waka_cli(), ["--config-write", "api-key=%s" % api_key])
	if err == -1:
		Utils.plugin_print("Failed to save API key")
	prompt.visible = false
	
func get_user_agent() -> String:
	"""Get user agent identifier"""
	return "godot/%s %s %s" % [get_engine_version(), _get_plugin_name(), get_plugin_version()]
	
func _get_plugin_name() -> String:
	"""Get name of the plugin"""
	return "Godot_Super-Wakatime"
	
func _get_plugin_version() -> String:
	"""Get plugin version"""
	return "1.0.0"
	
func get_engine_version() -> String:
	"""Get verison of currently used engine"""
	return "%s.%s.%s" % [Engine.get_version_info()["major"], Engine.get_version_info()["minor"], Engine.get_version_info()["patch"]]