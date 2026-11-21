"""Renders a contact sheet of every object in a .blend, each framed on its own.

    /Applications/Blender.app/Contents/MacOS/Blender --background assets/models/items/items.blend \\
        --python tools/blender/render_item_previews.py -- out.png [thumb_size] [name_filter]

name_filter "ALL" renders each top-level object together with its children
(use it for hero.blend, whose legs are separate child objects).

Uses EEVEE with a sun and a sky-ish world, on a neutral floor.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(args[0] if args else "previews.png")
SIZE = int(args[1]) if len(args) > 1 else 360
FILTER = args[2] if len(args) > 2 else ""

scene = bpy.context.scene
for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
scene.render.resolution_x = SIZE
scene.render.resolution_y = SIZE
scene.render.film_transparent = False
scene.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"

world = bpy.data.worlds.new("PreviewWorld")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.55, 0.65, 0.8, 1.0)
bg.inputs["Strength"].default_value = 0.9

sun_data = bpy.data.lights.new("Sun", "SUN")
sun_data.energy = 4.0
sun_data.angle = math.radians(3)
sun = bpy.data.objects.new("Sun", sun_data)
sun.rotation_euler = (math.radians(50), 0, math.radians(35))
scene.collection.objects.link(sun)

floor_mat = bpy.data.materials.new("Floor")
floor_mat.diffuse_color = (0.35, 0.35, 0.33, 1)
try:
    floor_mat.use_nodes = True
except (AttributeError, TypeError):
    pass
fb = next(n for n in floor_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
fb.inputs["Base Color"].default_value = (0.32, 0.33, 0.3, 1)
fb.inputs["Roughness"].default_value = 0.9
bpy.ops.mesh.primitive_plane_add(size=1.0)
floor = bpy.context.active_object
floor.data.materials.append(floor_mat)

cam_data = bpy.data.cameras.new("Cam")
cam_data.lens = 50
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

meshes = [o for o in bpy.data.objects if o.type == "MESH" and o is not floor]
if FILTER == "ALL":  # One frame with everything, e.g. a character made of several parts.
    items = [o for o in meshes if o.parent is None]
else:
    items = [o for o in meshes if FILTER in o.name]
tiles = []
tmp = OUT + ".tmp.png"
for obj in items:
    group = [obj] + list(obj.children_recursive) if FILTER == "ALL" else [obj]
    for o in meshes:
        o.hide_render = o not in group
    corners = [o.matrix_world @ Vector(c) for o in group for c in o.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    center = (lo + hi) / 2
    radius = (hi - lo).length / 2
    floor.location = (center.x, center.y, lo.z)
    floor.scale = (radius * 8, radius * 8, 1)
    direction = Vector((0.75, -1.0, 0.6)).normalized()
    dist = radius / math.tan(cam_data.angle / 2) * 1.05
    cam.location = center + direction * dist
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    cam_data.clip_start = dist * 0.01
    cam_data.clip_end = dist * 10
    scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp)
    px = np.array(img.pixels[:], np.float32).reshape(SIZE, SIZE, 4)
    tiles.append(px)
    bpy.data.images.remove(img)
    print("rendered", obj.name)

cols = min(6, len(tiles))
rows = (len(tiles) + cols - 1) // cols
sheet = np.ones((rows * SIZE, cols * SIZE, 4), np.float32)
for i, px in enumerate(tiles):
    r, c = divmod(i, cols)
    r = rows - 1 - r
    sheet[r * SIZE:(r + 1) * SIZE, c * SIZE:(c + 1) * SIZE] = px
out = bpy.data.images.new("sheet", cols * SIZE, rows * SIZE)
out.pixels.foreach_set(sheet.ravel())
out.filepath_raw = OUT
out.file_format = "PNG"
out.save()
os.remove(tmp)
print("Wrote", OUT, "order:", ", ".join(o.name for o in items))
