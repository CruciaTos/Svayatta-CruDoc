import bpy, json, re, sys
p="/home/claude/zanat/blend/Z-Anatomy/Startup.blend"
bpy.ops.wm.read_factory_settings(use_empty=True)
with bpy.data.libraries.load(p, link=False) as (src, dst):
    dst.collections=["Muscular system","Skeletal system"]
scene=bpy.context.scene
MS=bpy.data.collections["Muscular system"]; SK=bpy.data.collections["Skeletal system"]
SKIP=re.compile(r"bursa|tendon sheath|fascia|retinacul|aponeurosis of|linea alba|arch of|septum|ligament", re.I)
KEEP=re.compile(r"iliotibial tract|thoracolumbar|plantar aponeurosis|palmar aponeurosis|bicipital aponeurosis", re.I)
def colpath(o, root):
    # find path from root to a collection containing o
    def f(c, path):
        if o.name in c.objects: return path+[c.name]
        for ch in c.children:
            r=f(ch, path+[c.name])
            if r: return r
    return f(root, [])
def pick(root, kind):
    out=[]
    for o in root.all_objects:
        if o.type!='MESH': continue
        n=o.name
        if re.search(r"\.(j|g|t)$", n): continue
        if kind=='muscle' and SKIP.search(n) and not KEEP.search(n): continue
        out.append(o)
    return out
mus=pick(MS,'muscle'); bones=pick(SK,'bone')
print("muscles",len(mus),"bones",len(bones))
superficial=set(o.name for o in bpy.data.collections["Superficial muscles"].all_objects)
for c in list(scene.collection.children): scene.collection.children.unlink(c)
out=bpy.data.collections.new("OUT"); scene.collection.children.link(out)
dg=bpy.context.evaluated_depsgraph_get()
cat=[]
def bake(o, kind):
    for m in o.modifiers:
        if m.type=='SUBSURF': m.levels=0
        if m.type in ('HOOK','WIREFRAME'): m.show_viewport=False
    tmp=bpy.data.collections.new("tmp"); scene.collection.children.link(tmp); tmp.objects.link(o)
    dg=bpy.context.evaluated_depsgraph_get(); dg.update()
    ev=o.evaluated_get(dg)
    me=bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=False, depsgraph=dg)
    me.transform(o.matrix_world)
    scene.collection.children.unlink(tmp)
    me.materials.clear()
    side='R' if o.name.endswith('.r') else 'L' if o.name.endswith('.l') else 'M'
    base=re.sub(r"\.[rl]$","",o.name)
    idn=("m_" if kind=='muscle' else "b_")+re.sub(r"[^a-z0-9]+","_",base.lower()).strip("_")+("_"+side.lower() if side!='M' else "")
    no=bpy.data.objects.new(idn, me); out.objects.link(no)
    tris=sum(len(p.vertices)-2 for p in me.polygons)
    rec=dict(id=idn,name=base,side=side,kind=kind,tris=tris)
    if kind=='muscle':
        path=[]
        for ch in MS.children:
            if ch.name in ('Muscles','Superficial muscles'): continue
            r=colpath(o, ch)
            if r: path=r; break
        if not path: path=(colpath(o, MS) or [])[1:]
        rec.update(path=path, superficial=o.name in superficial,
                   action=[s.material.name for s in o.material_slots if s.material],
                   group=o.parent.name.rsplit('.',1)[0] if o.parent else None)
    else:
        rec.update(path=(colpath(o,SK) or [])[1:])
    cat.append(rec)
for i,o in enumerate(mus): bake(o,'muscle')
for i,o in enumerate(bones): bake(o,'bone')
# dedupe ids
seen={}
for r,o in zip(cat, list(out.objects)): pass
json.dump(cat, open("/home/claude/muscle/catalog_raw.json","w"), indent=0)
for o in list(bpy.data.objects):
    if o.name not in out.objects: bpy.data.objects.remove(o)
bpy.ops.export_scene.gltf(filepath="/home/claude/muscle/raw.glb", export_format='GLB', use_selection=False,
    export_apply=False, export_materials='NONE', export_normals=True, export_texcoords=False, export_yup=True, export_extras=False)
print("done", sum(r['tris'] for r in cat if r['kind']=='muscle'), sum(r['tris'] for r in cat if r['kind']=='bone'))
