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
	
