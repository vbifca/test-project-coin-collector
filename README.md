# Coin Collector (Godot 4.5)

Простая 2D-игра на **Godot 4.5**, где игрок управляет персонажем, собирающим монеты на случайно сгенерированной карте и избегает врагов.  
Игра поддерживает сохранение прогресса и настройку параметров через конфигурационные файлы.

# Раздел «Вопросы и ответы» для README (Godot 4.5)

Ниже — развернутые ответы на типовые вопросы по Godot, которые можно добавить в README проекта тестового задания. Примеры кода — на **GDScript** (Godot 4.5).

---

## Вопрос 1. Как работает система сцены в Godot и в чем ее преимущества?

**Сцена** в Godot — это иерархия узлов (nodes), сохраненная в `.tscn/.scn`. Любая сцена может быть переиспользуема как «префаб»: её инстанс добавляется в другую сцену. Сцены можно наследовать и объединять.

**Ключевые преимущества:**

* **Композиция**: собираете объект из узлов (графика, физика, логика) без жёсткой монолитности.
* **Повторное использование**: одна сцена — много инстансов (экономия времени и памяти).
* **Наследование сцен**: переопределение узлов и скриптов без дублирования.
* **Горячее редактирование**: изменения исходной сцены применяются ко всем инстансам.
* **Изоляция ответственности**: легче тестировать и отлаживать.

### Блок-схема простого платформера

Вариант с тремя экранами: загрузка → меню → игра.

```mermaid
flowchart TD
    A[Стартовый экран загрузки\n(логотип/текст, короткая задержка)] --> B[Экран меню\nКнопки: Играть, Выход]
    B -->|Играть| C[Игровая сцена\nПерсонаж + Противники + UI]
    C -->|Победа/Поражение| B
    B -->|Выход| D[Завершение приложения]
```

Мини-структура проектов:

```
Main.tscn        # стартовая сцена (Loader)
MainMenu.tscn    # меню
Game.tscn        # игровая сцена (мир, игрок, враги, UI)
```

---

## Вопрос 2. Как работают сигналы (Signals) в Godot?

**Сигналы** — реализация шаблона «наблюдатель». Узел `A` испускает сигнал, узел `B` подписывается на него — при этом `A` ничего не знает о `B` (слабая связность).

**Частые кейсы:**

* Встроенные сигналы (`pressed`, `timeout`, `area_entered`, …).
* Пользовательские сигналы: `signal coin_collected(amount)`.

**Пример: связь несвязанных узлов** (нет общего родителя) через **автозагрузку** (Singleton) `EventBus.gd`:

```gdscript
# EventBus.gd (Autoload)
signal coin_collected(value: int)

# Coin.gd — монетка
func _on_picked():
    EventBus.emit_signal("coin_collected", 1)

# UIManager.gd — интерфейс находится в другой сцене
func _ready():
    EventBus.coin_collected.connect(_on_coin)

func _on_coin(v: int) -> void:
    coins += v
    label.text = "Coins: %d" % coins
```

Альтернатива: прямое подключение по `NodePath` или через `get_tree().get_nodes_in_group("UI")`.

---

## Вопрос 3. Как в GDScript организовать наследование, и зачем это нужно?

Наследование — `extends BaseClass` или `extends "res://path/Base.gd"`. Позволяет выделять общую логику в базовый класс и переиспользовать её.

```gdscript
# EnemyBase.gd
extends CharacterBody2D
class_name EnemyBase
var speed := 120.0
func move_dir(dir: Vector2) -> void:
    velocity = dir.normalized() * speed
    move_and_slide()

# EnemyChaser.gd
extends EnemyBase
class_name EnemyChaser
func _physics_process(dt: float) -> void:
    var dir := (player.global_position - global_position)
    move_dir(dir)  # используем базовую реализацию
```

В Godot 4 можно вызывать метод родителя через `super()`:

```gdscript
func _ready() -> void:
    super() # вызов родительского _ready (если определён)
```

Зачем: уменьшение дублирования, единый контракт и поведение, удобные расширения.

---

## Вопрос 4. Как работает система импорта ресурсов в Godot? Что произойдет, если изменить исходный файл изображения?

При добавлении файла (png, wav и т.п.) Godot **импортирует** его в формат, оптимальный для движка/платформы (см. панель **Import**). Импортированные данные хранятся в скрытой папке `.godot/` (или `.import/` в Godot 3.x).

Если изменить исходный PNG **вне** Godot (перезаписать), редактор это обнаружит и **переимпортирует** ресурс автоматически согласно текущим настройкам Import (компрессия, фильтры, атласы и пр.). Все ссылки в сценах/скриптах останутся валидными.

---

## Вопрос 5. Что такое `_process()` и `_physics_process()` в GDScript и чем они отличаются?

* `_process(delta)` — вызывается **каждый кадр**, с переменным `delta`. Подходит для UI, анимаций, эффектов, некритичной логики.
* `_physics_process(delta)` — фиксированный такт физики (по умолчанию 60 Гц). Используйте для движения тел, работы с коллизиями, `move_and_slide()`.

Правило: **всё, что взаимодействует с физикой, делайте в `_physics_process()`**.

---

## Вопрос 6. Как создать и использовать таймер (Timer) в Godot?

**Способ 1: Узел Timer в сцене**

```gdscript
@onready var t: Timer = $Timer
func _ready():
    t.wait_time = 1.5
    t.one_shot = true
    t.start()
    t.timeout.connect(_on_timeout)

func _on_timeout() -> void:
    print("boom")
```

**Способ 2: Временный таймер от дерева**

```gdscript
await get_tree().create_timer(2.0).timeout
print("2 секунды спустя")
```

---

## Вопрос 7. Как работает система слоев и масок (Layers and Masks) для коллизий в Godot?

У каждого тела/области есть:

* **Collision Layer** — слой(и), на котором объект *находится*.
* **Collision Mask** — слои, с которыми он *сталкивается/пересекается*.

Столкновение происходит, если **Layer A ∈ Mask B** и **Layer B ∈ Mask A**. Это позволяет избирательно настраивать взаимодействия (например, пули сталкиваются с врагами, но не с игроком).

---

## Вопрос 8. Как в GDScript организовать взаимодействие между разными сценами или узлами?

* **Сигналы** (рекомендуется для слабой связности).
* **Группы**: `add_to_group("Enemy")`, поиск: `get_tree().get_nodes_in_group("Enemy")`.
* **Autoload (Singleton)** — общий менеджер/шина событий/сохраняемые данные.
* **NodePath** — прямое обращение: `get_node("../UI/ScoreLabel")`.
* **Посредник/Контроллер** — один узел владеет ссылками на участников и «склеивает» их.

---

## Вопрос 9. Как загрузить и инстанцировать сцену динамически во время выполнения игры?

```gdscript
var ps: PackedScene = preload("res://scenes/Coin.tscn") # или load()
var coin := ps.instantiate()
coin.global_position = Vector2(100, 100)
add_child(coin)
```

Для смены экрана: `get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")`.

---

## Вопрос 10. Какие средства профилирования и отладки предоставляет Godot? Как ими пользоваться?

* **Debugger** (нижняя панель): ошибки, предупреждения, пауза, стек вызовов, переменные.
* **Profiler**: время на кадр, вызовы функций, рендер, физика — помогает найти «узкие места».
* **Monitors** (перф-метрики в реальном времени): FPS, память, объекты и т.д.
* **Remote Inspector**: исследование дерева узлов запущенной игры.
* **Debug Draw**: визуализация коллизий (меню Debug → Visible Collision Shapes).
* **Логи**: `print`, `push_warning`, `push_error`.

---

## Вопрос 11. Как реализовать систему сохранения и загрузки данных игры в Godot?

Подходы:

1. **JSON через FileAccess** — просто и прозрачно.
2. **ConfigFile** — INI-подобный формат секций/ключей.
3. **Resources** — сериализация кастомных `Resource` с `ResourceSaver/Loader`.

**Пример (JSON):**

```gdscript
# Save
var data := {
    "player": {"pos": [player.global_position.x, player.global_position.y]},
    "score": score
}
var f := FileAccess.open("user://save.json", FileAccess.WRITE)
f.store_string(JSON.stringify(data))
f.close()

# Load
if FileAccess.file_exists("user://save.json"):
    var f := FileAccess.open("user://save.json", FileAccess.READ)
    var txt := f.get_as_text()
    var d := JSON.parse_string(txt)
    if typeof(d) == TYPE_DICTIONARY:
        var p := d.player.pos
        player.global_position = Vector2(p[0], p[1])
        score = int(d.score)
```

Рекомендация: храните **минимальный** набор состояния (позиции, счёт, оставшиеся монеты/враги). Операции, изменяющие сцену, лучше выполнять через `call_deferred`, чтобы не удалять узлы внутри физического колбэка.

---

## Вопрос 12. Как подключить и использовать Android плагины в Godot? Какие шаги необходимы для интеграции?

1. **Установить Android Build Template**: `Project → Install Android Build Template`.
2. **Добавить плагин**: поместить файлы плагина в `res://android/plugins/<PluginName>/<PluginName>.gdap` и AAR/Gradle-части по инструкции автора.
3. **Включить плагин**: в `Project → Export → Android → Options → Plugins` отметить плагин галочкой.
4. **Разрешения**: убедиться, что манифест/опции экспорта содержат нужные permissions.
5. **Вызов из GDScript**:

```gdscript
if Engine.has_singleton("MyAndroidPlugin"):
    var p = Engine.get_singleton("MyAndroidPlugin")
    p.some_method("hello")
```

6. **Сборка**: экспорт на Android с установленным SDK/Java/Gradle.

---


