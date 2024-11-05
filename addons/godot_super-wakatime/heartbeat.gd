var file_path
var entity
var type
var category
var time
var is_write
var cursorpos
var lines
var lineno
var line_additions
var line_deletions
var language
var project

func _init(file_path = '', time = 0, is_write = false):
    self.file_path = file_path
    self.time = time
    self.is_write = is_write