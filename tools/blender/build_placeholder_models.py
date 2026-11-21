"""Builds the low-poly placeholder models in assets/models/.

Run from the project root:
    /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
        --python tools/blender/build_placeholder_models.py

This OVERWRITES the .blend files it creates. Once you start editing a model by
hand in Blender, stop running this script (or delete that asset's entry below).

Conventions used (keep these for your own models too):
  * 1 Blender unit = 1 meter = 1 Godot unit.
  * Origin at the bottom center (the feet), so the model sits on the ground at y=0.
  * Characters face Blender's front view (-Y). After import that's Godot's +Z,
    so the player scene rotates the model 180 degrees to face Godot's forward (-Z).
  * Godot import hints in object names:
      "-col"         mesh + static trimesh collision
      "-convcol"     mesh + static convex collision
      "-convcolonly" invisible convex collision only
    See: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html
"""

import math
import os
import random

import bpy

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODELS_DIR = os.path.join(PROJECT_ROOT, "assets", "models")


# --- helpers -----------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, color, roughness=0.8, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    mat.diffuse_color = (*color, 1.0)  # viewport color in Solid mode
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        if emission is not None:
            bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def finalize(obj):
    """Apply rotation/scale so Godot gets clean transforms, and use flat shading."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.shade_flat()


def join(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    # Move the origin to the world origin (bottom center) without moving geometry.
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return joined


def cylinder(radius, depth, location, vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    return bpy.context.active_object


def cube(size, location):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, scale=size)
    return bpy.context.active_object


def save(relative_path):
    path = os.path.join(MODELS_DIR, relative_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
    print(f"Saved {path}")


# --- assets ------------------------------------------------------------------

def build_player():
    reset_scene()
    suit = make_material("Suit", (0.22, 0.5, 0.9), roughness=0.6)
    dark = make_material("Dark", (0.08, 0.09, 0.11), roughness=0.9)
    visor = make_material("Visor", (1.0, 0.75, 0.25), roughness=0.2,
                          emission=(1.0, 0.7, 0.2), emission_strength=1.5)

    parts = []
    for side in (-1, 1):
        leg = cylinder(0.11, 0.36, (0.15 * side, 0.0, 0.18), vertices=8)
        assign(leg, dark)
        parts.append(leg)
        arm = cylinder(0.09, 0.6, (0.45 * side, 0.0, 0.84), vertices=8)
        arm.rotation_euler = (0.0, math.radians(8 * side), 0.0)
        assign(arm, suit)
        parts.append(arm)

    body = cylinder(0.35, 0.85, (0.0, 0.0, 0.76), vertices=12)
    assign(body, suit)
    parts.append(body)

    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.28, location=(0.0, 0.0, 1.45))
    head = bpy.context.active_object
    assign(head, suit)
    parts.append(head)

    # The visor sits on the front (-Y) so you can see which way the character faces.
    face = cube((0.4, 0.12, 0.14), (0.0, -0.24, 1.47))
    assign(face, visor)
    parts.append(face)

    pack = cube((0.42, 0.2, 0.45), (0.0, 0.38, 0.86))
    assign(pack, dark)
    parts.append(pack)

    for part in parts:
        finalize(part)
    join(parts, "Player")
    save("characters/player.blend")


def build_tree():
    reset_scene()
    bark = make_material("Bark", (0.32, 0.2, 0.11), roughness=0.95)
    leaves = make_material("Leaves", (0.13, 0.42, 0.2), roughness=0.85)

    trunk = cylinder(0.18, 1.2, (0.0, 0.0, 0.6), vertices=7)
    assign(trunk, bark)
    parts = [trunk]
    for radius, depth, z in ((1.1, 1.6, 1.6), (0.85, 1.3, 2.3), (0.55, 1.0, 2.95)):
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=radius, radius2=0.0, depth=depth, location=(0.0, 0.0, z))
        cone = bpy.context.active_object
        cone.rotation_euler = (0.0, 0.0, random.uniform(0.0, math.tau))
        assign(cone, leaves)
        parts.append(cone)

    for part in parts:
        finalize(part)
    join(parts, "Tree")

    # Invisible collider around the trunk only, so you can walk under the branches' edge.
    collider = cylinder(0.3, 2.0, (0.0, 0.0, 1.0), vertices=8)
    collider.name = "TrunkCollision-convcolonly"
    save("props/tree.blend")


def build_rock():
    reset_scene()
    stone = make_material("Stone", (0.36, 0.36, 0.39), roughness=0.95)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.6, location=(0.0, 0.0, 0.0))
    rock = bpy.context.active_object
    for vertex in rock.data.vertices:
        vertex.co.x *= 1.25 + random.uniform(-0.12, 0.12)
        vertex.co.y *= 1.0 + random.uniform(-0.12, 0.12)
        vertex.co.z *= 0.7 + random.uniform(-0.1, 0.1)
    rock.location.z = 0.32
    assign(rock, stone)
    finalize(rock)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    rock.name = "Rock-convcol"  # mesh + convex collision in Godot
    save("props/rock.blend")


if __name__ == "__main__":
    random.seed(7)  # deterministic output
    build_player()
    build_tree()
    build_rock()
