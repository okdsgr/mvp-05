extends Node2D

# =====================================================================
# SUMERAGI - MVP-05
# ターン制対戦：何が何に勝つか
# =====================================================================

const WIN_W  : int    = 405
const WIN_H  : int    = 720
const N8N    : String = "https://okdsgr.app.n8n.cloud/webhook/"
const DESCENT_TIME : float = 180.0  # CPUエンティティが下まで降りる秒数

enum Phase { TITLE, CPU_SPAWNING, PLAYER_INPUT, WAITING_JUDGE, BATTLE_SCENE, NEXT_ROUND }
var _phase : Phase = Phase.TITLE

var _http_judge   : HTTPRequest = null
var _http_counter : HTTPRequest = null
var _ui           : CanvasLayer = null

# ゲーム状態
var _cpu_entity    : String = ""
var _cpu_entity_ja : String = ""
var _player_entity : String = ""
var _round         : int    = 0
var _player_score  : int    = 0
var _cpu_score     : int    = 0

# CPUエンティティの降下
var _descent_y     : float  = 0.0
var _descent_timer : float  = 0.0
var _cpu_lbl_node  : Label  = null

# 先攻CPU用エンティティリスト（第1ラウンドのみ）
const FIRST_ENTITIES : Array = [
["frog",       "カエル"],
["cockroach",  "ゴキブリ"],
["spider",     "クモ"],
["mouse",      "ネズミ"],
["crow",       "カラス"],
["jellyfish",  "クラゲ"],
["centipede",  "ムカデ"],
["wasp",       "スズメバチ"],
]

func _ready() -> void:
DisplayServer.window_set_size(Vector2i(WIN_W, WIN_H))
var scr := DisplayServer.screen_get_size()
DisplayServer.window_set_position(Vector2i((scr.x - WIN_W) / 2, (scr.y - WIN_H) / 2))
RenderingServer.set_default_clear_color(Color(0.05, 0.05, 0.12))

_ui = $UI

_http_judge = HTTPRequest.new()
_http_judge.timeout = 30.0
add_child(_http_judge)

_http_counter = HTTPRequest.new()
_http_counter.timeout = 30.0
add_child(_http_counter)

_show_title()

func _process(delta: float) -> void:
if _phase == Phase.PLAYER_INPUT and is_instance_valid(_cpu_lbl_node):
	_descent_timer += delta
	var progress := _descent_timer / DESCENT_TIME
	progress = clampf(progress, 0.0, 1.0)
	_descent_y = -60.0 + (WIN_H + 60.0) * progress
	_cpu_lbl_node.position.y = _descent_y

	# タイムゲージ更新
	var bar := _ui.get_node_or_null("TimeBar")
	if bar and bar is ProgressBar:
		(bar as ProgressBar).value = 1.0 - progress

	# 時間切れ → プレイヤーの負け
	if progress >= 1.0:
		_on_time_up()

# =====================================================================
# TITLE
# =====================================================================
func _show_title() -> void:
_phase = Phase.TITLE
_clear_ui()

var title := Label.new()
title.text = "AKINEMON"
title.add_theme_font_size_override("font_size", 64)
title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
title.position = Vector2(0, 240)
title.custom_minimum_size = Vector2(WIN_W, 0)
_ui.add_child(title)

var sub := Label.new()
sub.text = "アキねもん"
sub.add_theme_font_size_override("font_size", 22)
sub.add_theme_color_override("font_color", Color(0.75, 0.68, 0.4, 0.85))
sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
sub.position = Vector2(0, 328)
sub.custom_minimum_size = Vector2(WIN_W, 0)
_ui.add_child(sub)

var desc := Label.new()
desc.text = "おまかせあれ！たぶん当たる！"
desc.add_theme_font_size_override("font_size", 15)
desc.add_theme_color_override("font_color", Color(0.65, 0.7, 0.9, 0.8))
desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
desc.position = Vector2(0, 390)
desc.custom_minimum_size = Vector2(WIN_W, 0)
_ui.add_child(desc)

var btn := Button.new()
btn.text = "▶  ゲーム開始"
btn.custom_minimum_size = Vector2(260, 64)
btn.add_theme_font_size_override("font_size", 20)
btn.position = Vector2((WIN_W - 260) / 2, 520)
_ui.add_child(btn)
btn.pressed.connect(_start_game)

# =====================================================================
# GAME START
# =====================================================================
func _start_game() -> void:
_round        = 0
_player_score = 0
_cpu_score    = 0
_cpu_entity    = ""
_cpu_entity_ja = ""
_next_cpu_turn("")  # 第1ラウンドはランダム選択

func _next_cpu_turn(player_won_entity: String) -> void:
_round += 1
_phase = Phase.CPU_SPAWNING
_clear_ui()

var status := Label.new()
status.text = "ROUND %d
CPUが考えています…" % _round
status.add_theme_font_size_override("font_size", 22)
status.add_theme_color_override("font_color", Color(0.7, 0.75, 1.0))
status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
status.position = Vector2(0, 300)
status.custom_minimum_size = Vector2(WIN_W, 0)
_ui.add_child(status)

if player_won_entity.is_empty():
	# 第1ラウンド：ランダム
	var pick : Array = FIRST_ENTITIES[randi() % FIRST_ENTITIES.size()]
	_cpu_entity    = pick[0]
	_cpu_entity_ja = pick[1]
	await get_tree().create_timer(1.2).timeout
	_start_player_input_phase()
else:
	# CPUがカウンターを生成
	_call_cpu_counter(player_won_entity)

func _call_cpu_counter(winner: String) -> void:
var body := JSON.stringify({"winner": winner})
var headers : PackedStringArray = ["Content-Type: application/json"]
if _http_counter.request_completed.is_connected(_on_counter_response):
	_http_counter.request_completed.disconnect(_on_counter_response)
_http_counter.request_completed.connect(_on_counter_response, CONNECT_ONE_SHOT)
_http_counter.request(N8N + "cpu-counter", headers, HTTPClient.METHOD_POST, body)

func _on_counter_response(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
var text := body.get_string_from_utf8()
custom_print(["[Counter] code=", code, " body=", text.substr(0, 100]))
var json = JSON.parse_string(text)
if json and json.has("entity"):
	_cpu_entity    = str(json["entity"])
	_cpu_entity_ja = str(json.get("entity_ja", _cpu_entity))
else:
	# フォールバック
	var pick : Array = FIRST_ENTITIES[randi() % FIRST_ENTITIES.size()]
	_cpu_entity    = pick[0]
	_cpu_entity_ja = pick[1]
_start_player_input_phase()

# =====================================================================
# PLAYER INPUT PHASE
# =====================================================================
func _start_player_input_phase() -> void:
_phase = Phase.PLAYER_INPUT
_descent_timer = 0.0
_clear_ui()

# スコア表示
var score_lbl := Label.new()
score_lbl.name = "ScoreLabel"
score_lbl.text = "YOU %d  -  CPU %d  |  ROUND %d" % [_player_score, _cpu_score, _round]
score_lbl.add_theme_font_size_override("font_size", 14)
score_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.9, 0.85))
score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
score_lbl.position = Vector2(0, 14)
score_lbl.custom_minimum_size = Vector2(WIN_W, 0)
_ui.add_child(score_lbl)

# タイムゲージ
var bar := ProgressBar.new()
bar.name = "TimeBar"
bar.min_value = 0.0
bar.max_value = 1.0
bar.value     = 1.0
bar.show_percentage = false
bar.custom_minimum_size = Vector2(WIN_W - 40, 10)
bar.position = Vector2(20, 40)
_ui.add_child(bar)

# CPUエンティティ（降下アニメ）
_cpu_lbl_node = Label.new()
_cpu_lbl_node.name = "CPUEntity"
_cpu_lbl_node.text = "👾  %s" % _cpu_entity_ja
_cpu_lbl_node.add_theme_font_size_override("font_size", 42)
_cpu_lbl_node.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
_cpu_lbl_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
_cpu_lbl_node.custom_minimum_size = Vector2(WIN_W, 0)
_cpu_lbl_node.position = Vector2(0, -60.0)
_ui.add_child(_cpu_lbl_node)

# ヒント
var hint := Label.new()
hint.text = "「%s」に勝てるものを入力してください" % _cpu_entity_ja
hint.add_theme_font_size_override("font_size", 16)
hint.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
hint.autowrap_mode = TextServer.AUTOWRAP_WORD
hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
hint.custom_minimum_size = Vector2(WIN_W - 40, 0)
hint.position = Vector2(20, 560)
_ui.add_child(hint)

# 入力欄
var input := LineEdit.new()
input.name = "PlayerInput"
input.placeholder_text = "例: ヘビ、タカ、塩..."
input.custom_minimum_size = Vector2(270, 52)
input.add_theme_font_size_override("font_size", 18)
input.position = Vector2(20, 618)
_ui.add_child(input)

var btn := Button.new()
btn.name = "SubmitBtn"
btn.text = "決定"
btn.custom_minimum_size = Vector2(80, 52)
btn.add_theme_font_size_override("font_size", 18)
btn.position = Vector2(300, 618)
_ui.add_child(btn)
btn.pressed.connect(_on_player_submit)
var cb := func(_t: String): _on_player_submit()
input.text_submitted.connect(cb)

func _on_player_submit() -> void:
if _phase != Phase.PLAYER_INPUT:
	return
var input_node := _ui.get_node_or_null("PlayerInput")
if input_node == null:
	return
var text : String = (input_node as LineEdit).text.strip_edges()
if text.is_empty():
	return
_player_entity = text
_call_battle_judge()

func _on_time_up() -> void:
_cpu_score += 1
_show_battle_scene("TIME UP…", [
	"時間切れ！",
	"%s が降りてきてしまった…" % _cpu_entity_ja,
	"CPUの勝利！",
], false)

# =====================================================================
# BATTLE JUDGE
# =====================================================================
func _call_battle_judge() -> void:
_phase = Phase.WAITING_JUDGE

# 入力欄・ボタンを無効化
var btn := _ui.get_node_or_null("SubmitBtn")
if btn and btn is Button:
	(btn as Button).disabled = true
var inp := _ui.get_node_or_null("PlayerInput")
if inp and inp is LineEdit:
	(inp as LineEdit).editable = false

var body := JSON.stringify({"player": _player_entity, "cpu": _cpu_entity})
var headers : PackedStringArray = ["Content-Type: application/json"]
if _http_judge.request_completed.is_connected(_on_judge_response):
	_http_judge.request_completed.disconnect(_on_judge_response)
_http_judge.request_completed.connect(_on_judge_response, CONNECT_ONE_SHOT)
_http_judge.request(N8N + "battle-judge", headers, HTTPClient.METHOD_POST, body)

func _on_judge_response(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
var text := body.get_string_from_utf8()
custom_print(["[Judge] code=", code, " body=", text.substr(0, 200]))
var json = JSON.parse_string(text)

if json == null or not json.has("winner"):
	_show_battle_scene("エラー", ["判定に失敗しました。もう一度お試しください。"], false)
	return

var player_wins : bool = str(json["winner"]) == "player"
var reason      : String = str(json.get("reason", ""))
var scene       : Array  = []
if json.has("scene") and json["scene"] is Array:
	scene = json["scene"]
else:
	scene = [reason]

if player_wins:
	_player_score += 1
	_show_battle_scene("YOU WIN！", scene, true)
else:
	_cpu_score += 1
	_show_battle_scene("CPU WIN…", scene, false)

# =====================================================================
# BATTLE SCENE
# =====================================================================
func _show_battle_scene(headline: String, scene_lines: Array, player_wins: bool) -> void:
_phase = Phase.BATTLE_SCENE
_clear_ui()

# スコア
var score_lbl := Label.new()
score_lbl.text = "YOU %d  -  CPU %d" % [_player_score, _cpu_score]
score_lbl.add_theme_font_size_override("font_size", 14)
score_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.9, 0.85))
score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
score_lbl.position = Vector2(0, 14)
score_lbl.custom_minimum_size = Vector2(WIN_W, 0)
_ui.add_child(score_lbl)

# 見出し
var h := Label.new()
h.text = headline
h.add_theme_font_size_override("font_size", 48)
h.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55) if player_wins else Color(1.0, 0.38, 0.38))
h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
h.position = Vector2(0, 60)
h.custom_minimum_size = Vector2(WIN_W, 0)
_ui.add_child(h)

# 対戦表示
var match_lbl := Label.new()
match_lbl.text = "%s  VS  %s" % [_player_entity, _cpu_entity_ja]
match_lbl.add_theme_font_size_override("font_size", 20)
match_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 1.0, 0.9))
match_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
match_lbl.position = Vector2(0, 130)
match_lbl.custom_minimum_size = Vector2(WIN_W, 0)
_ui.add_child(match_lbl)

# 演出テキスト（順番に表示）
var y := 210.0
for i : int in scene_lines.size():
	var line_lbl := Label.new()
	line_lbl.text = str(scene_lines[i])
	line_lbl.add_theme_font_size_override("font_size", 18)
	line_lbl.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	line_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	line_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line_lbl.custom_minimum_size = Vector2(WIN_W - 40, 0)
	line_lbl.position = Vector2(20, y)
	line_lbl.modulate.a = 0.0
	_ui.add_child(line_lbl)

	var tw := create_tween()
	tw.tween_interval(float(i) * 0.8)
	tw.tween_property(line_lbl, "modulate:a", 1.0, 0.4)
	y += 70.0

# 次へボタン（演出後に表示）
var next_btn := Button.new()
next_btn.text = "次のラウンド ▶" if player_wins else "続ける ▶"
next_btn.custom_minimum_size = Vector2(260, 60)
next_btn.add_theme_font_size_override("font_size", 18)
next_btn.position = Vector2((WIN_W - 260) / 2, 612)
next_btn.modulate.a = 0.0
_ui.add_child(next_btn)

var wait_time := float(scene_lines.size()) * 0.8 + 0.4
var tw2 := create_tween()
tw2.tween_interval(wait_time)
tw2.tween_property(next_btn, "modulate:a", 1.0, 0.3)

if player_wins:
	next_btn.pressed.connect(func(): _next_cpu_turn(_player_entity))
else:
	next_btn.pressed.connect(func(): _next_cpu_turn(""))

func _clear_ui() -> void:
for c : Node in _ui.get_children():
	c.queue_free()
_cpu_lbl_node = null
