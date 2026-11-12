"""Blender-side helpers: mesh objects, materials, workbench rendering, tiling."""
import math
import numpy as np
import bpy
from mathutils import Vector, Matrix


# ----------------------------------------------------------------- meshes
def make_mesh_object(name, V, T, N=None, C=None, material=None, collection=None):
    V = np.asarray(V, np.float32)
    T = np.asarray(T, np.int32)
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(V))
    me.vertices.foreach_set('co', V.ravel())
    me.loops.add(len(T) * 3)
    me.polygons.add(len(T))
    me.loops.foreach_set('vertex_index', T.ravel())
    me.polygons.foreach_set('loop_start', np.arange(0, len(T) * 3, 3, dtype=np.int32))
    me.polygons.foreach_set('loop_total', np.full(len(T), 3, np.int32))
    me.polygons.foreach_set('use_smooth', np.ones(len(T), bool))
    me.update(calc_edges=True)
    me.validate()
    if N is not None:
        me.normals_split_custom_set_from_vertices([tuple(n) for n in np.asarray(N, np.float64)])
    if C is not None:
        ca = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
        col = np.ones((len(V), 4), np.float32)
        col[:, 0] = col[:, 1] = col[:, 2] = np.asarray(C, np.float32)
        ca.data.foreach_set('color', col.ravel())
        me.color_attributes.active_color = ca
        me.color_attributes.render_color_index = list(me.color_attributes).index(ca)
    ob = bpy.data.objects.new(name, me)
    (collection or bpy.context.scene.collection).objects.link(ob)
    if material is not None:
        me.materials.append(material)
    return ob


def tri_count(ob):
    me = ob.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


# -------------------------------------------------------------- materials
def _set(bsdf, names, value):
    for n in names:
        if n in bsdf.inputs:
            try:
                bsdf.inputs[n].default_value = value
            except Exception:
                pass
            return


def make_material(name, color, rough=0.5, metallic=0.0, sss=0.0, sss_color=None, aniso=0.0, viewport=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    _set(b, ['Base Color'], color)
    _set(b, ['Roughness'], rough)
    _set(b, ['Metallic'], metallic)
    if sss > 0:
        _set(b, ['Subsurface Weight', 'Subsurface'], sss)
        _set(b, ['Subsurface Radius'], (1.0, 0.4, 0.25))
        _set(b, ['Subsurface Scale'], 0.6)
    if aniso > 0:
        _set(b, ['Anisotropic'], aniso)
    m.diffuse_color = viewport or color
    m.roughness = rough
    m.metallic = metallic
    return m


def make_materials():
    d = {}
    d['enamel'] = make_material('mat_enamel', (0.93, 0.90, 0.82, 1), 0.25, 0.0, sss=0.35, viewport=(0.93, 0.9, 0.82, 1))
    d['pulp'] = make_material('mat_pulp', (0.78, 0.18, 0.2, 1), 0.45, 0.0, sss=0.6, viewport=(0.78, 0.18, 0.2, 1))
    d['titanium'] = make_material('mat_titanium', (0.72, 0.73, 0.76, 1), 0.35, 1.0, aniso=0.6, viewport=(0.72, 0.73, 0.76, 1))
    d['steel'] = make_material('mat_steel', (0.80, 0.82, 0.85, 1), 0.3, 1.0, viewport=(0.8, 0.82, 0.85, 1))
    d['post'] = make_material('mat_post', (0.93, 0.90, 0.80, 1), 0.5, 0.0, viewport=(0.93, 0.90, 0.8, 1))
    return d


# --------------------------------------------------------------- render
def setup_render(scene, w, h, bg=(0.42, 0.44, 0.47)):
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'Standard'
    d = scene.display
    d.render_aa = '8'
    d.shading.light = 'STUDIO'
    d.shading.studio_light = 'Default' if False else d.shading.studio_light
    d.shading.color_type = 'MATERIAL'
    d.shading.show_cavity = True
    d.shading.cavity_type = 'BOTH'
    d.shading.cavity_ridge_factor = 1.2
    d.shading.cavity_valley_factor = 1.4
    d.shading.curvature_ridge_factor = 0.0
    d.shading.show_object_outline = True
    d.shading.object_outline_color = (0.05, 0.05, 0.06)
    d.shading.show_specular_highlight = True
    if scene.world is None:
        scene.world = bpy.data.worlds.new('W')
    scene.world.color = bg


def get_camera(scene):
    cam = scene.camera
    if cam is None:
        cd = bpy.data.cameras.new('cam')
        cam = bpy.data.objects.new('cam', cd)
        scene.collection.objects.link(cam)
        scene.camera = cam
    cam.data.type = 'ORTHO'
    return cam


def aim_camera(cam, centre, direction, up, scale, dist=400.0):
    d = Vector(direction).normalized()
    cam.location = Vector(centre) - d * dist
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler() if up is None else _look(d, Vector(up))
    cam.data.ortho_scale = scale
    cam.data.clip_start = 1.0
    cam.data.clip_end = 2000.0


def _look(d, up):
    z = -d.normalized()
    x = up.cross(z).normalized()
    y = z.cross(x)
    m = Matrix(((x.x, y.x, z.x), (x.y, y.y, z.y), (x.z, y.z, z.z)))
    return m.to_euler()


def render_to(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def load_pixels(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return a.reshape(h, w, 4)


def save_pixels(arr, path):
    h, w = arr.shape[:2]
    img = bpy.data.images.new('out', w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(arr, np.float32).ravel())
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)


def tile_images(tiles, ncols, pad=4):
    """tiles: list of (h,w,4) arrays of equal size, row-major top to bottom."""
    nrows = (len(tiles) + ncols - 1) // ncols
    h, w = tiles[0].shape[:2]
    out = np.full((nrows * (h + pad) + pad, ncols * (w + pad) + pad, 4), 0.1, np.float32)
    out[..., 3] = 1.0
    for i, t in enumerate(tiles):
        r, c = divmod(i, ncols)
        y0 = out.shape[0] - pad - (r + 1) * h - r * pad  # images are bottom-up
        x0 = pad + c * (w + pad)
        out[y0:y0 + h, x0:x0 + w] = t
    return out
