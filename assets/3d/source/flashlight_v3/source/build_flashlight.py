import bpy, math, random, os
from mathutils import Vector
OUT=os.path.abspath('outputs/flashlight')
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
random.seed(31)
def mat(name, color, metal, rough):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1); p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
 return m
body=mat('Anodized charcoal',(.055,.062,.058),.8,.38)
edge=mat('Worn aluminium edges',(.25,.27,.25),.9,.32)
rubber=mat('Rubber switch',(.016,.018,.016),0,.76)
reflector=mat('Reflector satin aluminium',(.65,.67,.65),1,.19)
glass=mat('Lens',(.19,.27,.25),.35,.12)
glass.diffuse_color=(.19,.27,.25,.14)
glass.node_tree.nodes.get('Principled BSDF').inputs['Alpha'].default_value=.14
glass.surface_render_method='DITHERED'
led=mat('Warm LED phosphor',(.86,.73,.35),.1,.33)
# Packed UV texture: fine finish, sparse scratches, subdued wear.
import numpy as np
n=512; rng=np.random.default_rng(31)
base=np.zeros((n,n,4),dtype=np.float32); noise=rng.normal(0,.006,(n,n))
for c,v in enumerate((.055,.062,.058)): base[:,:,c]=np.maximum(.005,v+noise)
base[:,:,3]=1
for i in range(160):
 x=int(rng.integers(n)); y=int(rng.integers(n)); length=int(rng.integers(2,25))
 base[y:min(n,y+length),x,:3]+=float(rng.uniform(.025,.1))
im=bpy.data.images.new('Charcoal wear 512',width=n,height=n); im.pixels.foreach_set(base.ravel()); im.filepath_raw=OUT+'/charcoal_albedo.png'; im.file_format='PNG'; im.save(); im.pack()
tex=body.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=im; body.node_tree.links.new(tex.outputs['Color'],body.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
parts=[]
def lathe(name,profile,material,segments=64):
 vs=[]; fs=[]
 for y,r in profile:
  for i in range(segments):
   a=i*2*math.pi/segments; vs.append((r*math.cos(a),y,r*math.sin(a)))
 for j in range(len(profile)-1):
  for i in range(segments):
   a=j*segments+i; b=j*segments+(i+1)%segments; fs.append((a,a+segments,b+segments,b))
 me=bpy.data.meshes.new(name); me.from_pydata(vs,[],fs); me.update()
 ob=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob); ob.data.materials.append(material); parts.append(ob)
 for p in me.polygons:p.use_smooth=True
 uv=me.uv_layers.new()
 for p in me.polygons:
  for li in p.loop_indices:
   vi=me.loops[li].vertex_index; uv.data[li].uv=(vi%segments/segments,vi//segments/max(1,len(profile)-1))
 return ob
lathe('Body',[(0,0),(.001,.016),(.006,.018),(.026,.018),(.03,.017),(.15,.017),(.158,.019),(.175,.027),(.193,.031),(.224,.031),(.228,.029),(.228,0)],body)
lathe('Tail cap',[(0,0),(-.004,.014),(-.003,.018),(.001,.019),(.019,.019),(.021,.017)],body)
for y in [.004,.008,.012,.016,.032,.038,.142,.148,.158,.166,.194,.200,.206,.212]:
 r=.019 if y<.03 else .0178 if y<.155 else .020 if y<.17 else .0316
 lathe('Machined grip ring',[(y-.0006,r-.0005),(y,r),(y+.0006,r-.0005)],body)
for i in range(40):
 a=i*math.tau/40
 bpy.ops.mesh.primitive_cube_add(size=1,location=(.017*math.cos(a),.089,.017*math.sin(a)))
 ob=bpy.context.object; ob.name='Grip flute'; ob.dimensions=(.0015,.097,.0013); ob.rotation_euler.y=-a; ob.data.materials.append(body); parts.append(ob)
 bevel=ob.modifiers.new('Soft machining','BEVEL'); bevel.width=.00045; bevel.segments=2
 bpy.context.view_layer.objects.active=ob; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); bpy.ops.object.modifier_apply(modifier=bevel.name)
lathe('Bezel rim',[(.222,.031),(.225,.032),(.229,.032),(.231,.030),(.231,.0275),(.228,.0275)],edge)
lathe('Reflector bowl',[(.229,.027),(.225,.026),(.214,.019),(.208,.007),(.208,.004)],reflector)
lathe('LED seat',[(.209,0),(.209,.005),(.210,.005),(.210,0)],led)
lathe('Lens',[(.229,0),(.229,.0268),(.2294,.0268),(.2294,0)],glass)
# Rubber side button on top, with protective metal surround.
for name,r,depth,z,material in [('Switch collar',.008,.003,.019,edge),('Switch',.0065,.003,.021,rubber)]:
 bpy.ops.mesh.primitive_cylinder_add(vertices=40,radius=r,depth=depth,location=(0,.153,z)); ob=bpy.context.object; ob.name=name; ob.data.materials.append(material); parts.append(ob)
 bevel=ob.modifiers.new('Rounded rim','BEVEL'); bevel.width=.0008; bevel.segments=3; bpy.ops.object.modifier_apply(modifier=bevel.name)
root=bpy.data.objects.new('Flashlight',None); bpy.context.collection.objects.link(root)
for ob in parts:ob.parent=root
bpy.ops.object.select_all(action='DESELECT')
for ob in parts+[root]:ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT+'/flashlight.glb',export_format='GLB',use_selection=True)
# Studio preview; studio objects stay out of the exported asset.
floor=mat('Studio ochre',(.13,.115,.075),0,.86)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.033)); bpy.context.object.data.materials.append(floor)
world=bpy.context.scene.world; world.color=(.18,.18,.18)
def area(loc,power,size):
 bpy.ops.object.light_add(type='AREA',location=loc); o=bpy.context.object; o.data.energy=power; o.data.shape='DISK'; o.data.size=size; o.rotation_euler=(Vector((0,.11,0))-o.location).to_track_quat('-Z','Y').to_euler()
area((.15,.12,.35),18,.25); area((-.2,.25,.12),10,.18); area((.05,-.25,.1),5,.15)
bpy.ops.object.camera_add(location=(.34,.40,.25)); cam=bpy.context.object; cam.rotation_euler=(Vector((0,.11,0))-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.type='ORTHO'; cam.data.ortho_scale=.37
s=bpy.context.scene; s.camera=cam; s.render.engine='CYCLES'; s.cycles.samples=48; s.render.resolution_x=1200; s.render.resolution_y=900; s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG'; s.render.filepath=OUT+'/preview.png'
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/flashlight.blend'); bpy.ops.render.render(write_still=True)
print('ASSET_TRIANGLES',sum(len(o.data.polygons) for o in parts if o.type=='MESH'))
