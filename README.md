# Ilestranstras Domain

3D top-down game, built with **Godot 4.7** (Forward+), models made in **Blender 5.x**.

## Running the game

1. Open Godot. In the Project Manager click **Import**, pick this folder's `project.godot`, then **Open**.
   (The first open takes a moment while Godot imports assets, including the `.blend` files via Blender.)
2. Press **F5** (or the ▶ **Run Project** button, top right). That starts from the splash screen.
3. Handy while developing:
   - **F6** (▶ with a clapperboard) runs only the scene you have open, e.g. open `scenes/sandbox/sandbox.tscn` and press F6 to skip the menus.
   - **F8** stops the game.
   - Errors and `print()` output show in the **Output** / **Debugger** panels at the bottom.

## The game: rolling field

**Play** loads `scenes/levels/rolling_field/`. You push a sticky ball around a field. Anything
whose longest side is at most **half the ball's diameter** sticks to it, and the ball grows.
Anything bigger is a solid obstacle until you're big enough. Small things are near the start,
houses and towers near the walls. Reach a 10 m ball to hit the goal (you can keep rolling).

The camera is third person: it sits behind the character and always faces where they face.

| Action | Keys |
| --- | --- |
| Roll forward / back | W / S (up / down arrows) |
| Turn (the character walks around the ball, the camera follows) | A / D, Q / E, or hold right mouse and drag |
| Zoom | Mouse wheel |
| Pause | Esc or P |

Tuning knobs are exported on the `Ball` node in `rolling_field.tscn` (pickup ratio, growth,
speed, turn speed, character size) and `TIERS` in `rolling_field.gd` (how many things of each
size spawn where).

## Sandbox controls

The old sandbox (`scenes/sandbox/sandbox.tscn`, run it with F6) uses the top-down `Player`:

| Action | Keys |
| --- | --- |
| Move | WASD / arrow keys (relative to the camera) |
| Aim | Mouse: the character faces the cursor |
| Primary action (shoot in the sandbox) | Left mouse (hold) |
| Rotate camera | Q / E, or hold right mouse and drag |
| Zoom | Mouse wheel |
| Pause | Esc or P |

All of these are named **input actions** (Project > Project Settings > Input Map).
Code only refers to action names like `"move_forward"`, so rebinding keys never needs code changes.

## Folder layout

```
autoloads/            Global singletons, always loaded (see "Startup")
  game.gd             Game flow: start, pause, return to menu, quit. Scene paths live here.
  scene_manager.gd    Fade transitions + background loading. Use it for every scene change.
  settings.gd         Volume / fullscreen / vsync, saved to user://settings.cfg
scenes/
  boot/splash.tscn    First scene that runs
  ui/                 Main menu, settings menu, pause menu
  camera/             TopDownCamera: follow, rotate, zoom, "what's under the mouse"   (keep)
  player/             Player: camera-relative movement, faces the cursor             (keep)
  ball/               StickyBall (roll, pick up, grow, character pushes it) + Collectible
  levels/rolling_field/   The game level, its ground shader and ItemCatalog (builds the things to pick up)
  sandbox/            Throwaway demo level                                           (delete me)
assets/
  models/             .blend files, imported by Godot directly
  audio/  textures/  fonts/   (create these as you need them)
resources/
  audio/default_bus_layout.tres   Audio buses: Master, Music, SFX
  theme/main_theme.tres           UI look (buttons, panels, label sizes)
tools/blender/        Python script that generated the placeholder models (ignored by Godot)
```

## How it fits together

**Startup:** Godot loads the autoloads in order (`Settings` → `SceneManager` → `Game` → `PauseMenu`),
which applies saved settings before anything is drawn. Then the main scene
(`scenes/boot/splash.tscn`) runs and hands off to the main menu.

```
Splash ──▶ Main Menu ──Play──▶ Gameplay scene (Game.GAMEPLAY_SCENE)
              ▲    └─Settings      │ Esc   (currently the rolling field)
              │                    ▼
              └────Main Menu─── Pause Menu ──Resume──▶ back to gameplay
                                   └─Settings / Quit
```

**Pausing:** `Game.set_paused(true)` sets `get_tree().paused`. Nodes stop processing unless their
**Process > Mode** is *Always* (menus, `SceneManager`) or *When Paused*. Anything in a gameplay scene
pauses automatically. The pause menu only responds while `Game.is_in_gameplay` is true.

**Changing scenes:** call `SceneManager.change_scene("res://...")`, not `get_tree().change_scene_to_file()`.
New scenes always start unpaused.

**Collision layers** (Project Settings > Layer Names > 3D Physics):
1 `world`, 2 `player`, 3 `props`, 4 `projectiles`, 5 `pickups`.
A body's *layer* is what it **is**; its *mask* is what it **collides with / detects**.

**Physics interpolation** is on, so movement stays smooth on 120/144 Hz monitors even though physics
runs at 60 Hz. Move physics things in `_physics_process`. After teleporting a node, call
`reset_physics_interpolation()` so it doesn't visibly slide.

**Static typing:** scripts use typed GDScript (`var speed: float = 7.0`, `func f() -> void`).
The project warns about untyped declarations, which catches bugs early and speeds the game up.

## Blender → Godot workflow

- Save `.blend` files anywhere under `assets/models/`. Godot re-imports them every time you save in
  Blender. (If Godot ever can't find Blender: Editor > Editor Settings > FileSystem > Import > Blender Path,
  set it to `/Applications/Blender.app`.)
- 1 Blender unit = 1 meter. Put the origin at the bottom center (feet), and apply rotation/scale (Ctrl+A).
- Model characters facing Blender's **front** (-Y). The player scene rotates the model 180° because
  Godot's forward is -Z.
- Name suffixes generate collision on import: `-col` (exact), `-convcol` (convex), `-convcolonly`
  (invisible collider only). See `tree.blend` and `rock.blend`.
- To change import options (materials, scale, animations), double-click the `.blend` in Godot's
  FileSystem dock to open the Advanced Import Settings.
- `tools/blender/build_placeholder_models.py` regenerates the placeholder models and **overwrites**
  them. Don't run it after you've hand-edited them.

## Removing the sandbox

The sandbox (`scenes/sandbox/`) is just a toy. To start the real game:

1. Make your level, e.g. `scenes/levels/level_01.tscn` (root: `Node3D`). Add a `WorldEnvironment`,
   a `DirectionalLight3D`, some ground with collision, and instance `scenes/player/player.tscn` and
   `scenes/camera/top_down_camera.tscn`. In the Inspector, set the player's **Camera** to the
   camera node and the camera's **Target** to the player.
2. In `autoloads/game.gd`, point `GAMEPLAY_SCENE` at your level.
3. Delete the `scenes/sandbox/` folder (in Godot's FileSystem dock, so references get updated).
4. Optional: delete the tree/rock models in `assets/models/props/` if you don't want them.

Nothing outside `scenes/sandbox/` depends on it.

## Where your settings are saved

`user://settings.cfg`, which on macOS is
`~/Library/Application Support/Godot/app_userdata/ilestranstras-domain/settings.cfg`.
Delete it to reset to the defaults.
