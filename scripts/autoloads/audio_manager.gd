extends Node
## AudioManager — музыка, звуки и эмбиенс.
##
## - Гарантирует существование шин Master / Music / SFX / Ambience,
##   даже если default_bus_layout.tres ещё не создан в редакторе.
## - Музыка: два плеера и кроссфейд между треками.
## - SFX: небольшой пул плееров, чтобы звуки могли перекрываться.
##
## Громкости шин настраивает SettingsManager (по именам шин ниже).

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMBIENCE := "Ambience"
const SFX_POOL_SIZE := 8

var _music_players: Array[AudioStreamPlayer] = []
var _active_music_index := 0
var _music_tween: Tween
var _sfx_players: Array[AudioStreamPlayer] = []
var _current_music: AudioStream


func _init() -> void:
	_ensure_buses()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()

	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_MUSIC
		add_child(player)
		_music_players.append(player)

	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_sfx_players.append(player)


## Включить музыку с кроссфейдом. Повторный вызов с тем же треком — no-op.
func play_music(stream: AudioStream, fade_seconds: float = 1.0) -> void:
	if stream == null or stream == _current_music:
		return
	_current_music = stream

	var next_index := 1 - _active_music_index
	var next_player := _music_players[next_index]
	var current_player := _music_players[_active_music_index]
	_active_music_index = next_index

	next_player.stream = stream
	next_player.volume_db = -80.0
	next_player.play()

	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(next_player, "volume_db", 0.0, fade_seconds)
	if current_player.playing:
		_music_tween.tween_property(current_player, "volume_db", -80.0, fade_seconds)
		_music_tween.chain().tween_callback(current_player.stop)


## Остановить музыку (с затуханием, если fade_seconds > 0).
func stop_music(fade_seconds: float = 0.5) -> void:
	_current_music = null
	var current_player := _music_players[_active_music_index]
	if not current_player.playing:
		return
	if fade_seconds <= 0.0:
		current_player.stop()
		return
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(current_player, "volume_db", -80.0, fade_seconds)
	_music_tween.tween_callback(current_player.stop)


## Разовый звук. pitch_scale удобно чуть варьировать для однотипных SFX.
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null:
		return
	for player in _sfx_players:
		if not player.playing:
			player.stream = stream
			player.volume_db = volume_db
			player.pitch_scale = pitch_scale
			player.play()
			return
	# Пул занят целиком — переиспользуем первый плеер.
	var fallback := _sfx_players[0]
	fallback.stream = stream
	fallback.volume_db = volume_db
	fallback.pitch_scale = pitch_scale
	fallback.play()


func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX, BUS_AMBIENCE]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var index := AudioServer.bus_count
			AudioServer.add_bus(index)
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, BUS_MASTER)
