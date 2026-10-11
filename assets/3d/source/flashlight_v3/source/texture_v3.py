# One shared 1K PBR atlas for all opaque parts. The separate lens is transparent.
src=bpy.data.images.load(os.path.abspath('work/metal_plate_02_rough_1k.jpg'))
src.colorspace_settings.name='Non-Color'; src.scale(512,512)
pixels=np.array(src.pixels[:],dtype=np.float32).reshape(512,512,4)
surface=pixels[:,:,:3].mean(axis=2)
surface=(surface-surface.min())/max(.001,float(surface.max()-surface.min()))
N=1024; T=512; rng=np.random.default_rng(487)
al=np.ones((N,N,4),np.float32); orm=np.ones_like(al); normals=np.ones_like(al)
normals[:,:,:3]=(.5,.5,1)
yy,xx=np.mgrid[0:T,0:T]; u=xx/(T-1); v=yy/(T-1)
for tile in range(4):
 y0=(tile//2)*T; x0=(tile%2)*T
 chips=np.zeros((T,T),np.float32); scratches=np.zeros_like(chips)
 # Abrasion follows rim contact, with broken angular boundaries, not round spots.
 edge_band=np.exp(-v*100)+np.exp(-(1-v)*90)
 broken=np.clip((surface-.42)*5,0,1)
 chips=edge_band*broken
 for _ in range(22 if tile==0 else 6):
  x=int(rng.integers(T)); y=int(rng.choice([rng.integers(0,28),rng.integers(T-25,T)])); length=int(rng.integers(4,30))
  for step in range(length):
   sx=(x+step)%T; sy=int(y+math.sin(step*.7)*2+rng.integers(-1,2))
   if 0<=sy<T:
    chips[max(0,sy-1):min(T,sy+2),sx]=rng.uniform(.4,.95)
 for _ in range(95):
  x=int(rng.integers(T)); y=int(rng.integers(T)); length=int(rng.integers(3,70)); slope=rng.uniform(-.6,.6)
  for step in range(length):
   sx=int(x+slope*step); sy=y+step
   if 0<=sx<T and 0<=sy<T:scratches[sy,sx]=rng.uniform(.1,.6)
 noise=rng.normal(0,.0015,(T,T))
 dirt=np.clip((surface-.35)*1.6,0,1)
 if tile==0:
  base=np.zeros((T,T,3))+(.012,.015,.014)
  base*= (1-dirt*.45)[:,:,None]
  wear=np.clip(chips*.85+scratches*.35,0,.95)
  base=base*(1-wear[:,:,None])+np.array((.28,.29,.275))*wear[:,:,None]
  rough=np.clip(.31+surface*.17-wear*.09,.22,.68); metal=np.clip(.72+wear*.25-dirt*.12,0,1)
 elif tile==1:
  base=np.zeros((T,T,3))+(.63,.65,.62); base*= (.85+surface*.15)[:,:,None]
  rough=.14+surface*.12+scratches*.08; metal=np.ones_like(u)*.98
 elif tile==2:
  base=np.zeros((T,T,3))+(.026,.029,.024); base+=dirt[:,:,None]*.025
  rough=.72+surface*.19; metal=np.zeros_like(u)
 else:
  base=np.zeros((T,T,3))+(.72,.58,.21); rough=np.ones_like(u)*.45; metal=np.zeros_like(u)
 al[y0:y0+T,x0:x0+T,:3]=np.clip(base+noise[:,:,None],.003,1)
 orm[y0:y0+T,x0:x0+T,1]=rough; orm[y0:y0+T,x0:x0+T,2]=metal
 # Diamond knurl: matching crossed cuts; no longitudinal flute geometry.
 h=(surface-.5)*.004-scratches*.01
 if tile==0:
  grip=(v>.155)&(v<.61)
  diamond=np.minimum(np.abs(np.sin((u*40+v*96)*math.pi)),np.abs(np.sin((u*40-v*96)*math.pi)))
  h+=grip*diamond*.12
  # Slightly polished peaks retain the dark finish and catch the hand light.
  al[y0:y0+T,x0:x0+T,:3]+= (grip*diamond*.006)[:,:,None]
 dx=np.gradient(h,axis=1)*18; dy=np.gradient(h,axis=0)*18
 normal=np.stack((-dx,-dy,np.ones_like(dx)),axis=2); normal/=np.linalg.norm(normal,axis=2)[:,:,None]
 normals[y0:y0+T,x0:x0+T,:3]=normal*.5+.5
def save_tex(name,data,linear=False):
 im=bpy.data.images.new(name,width=N,height=N)
 if linear:im.colorspace_settings.name='Non-Color'
 im.pixels.foreach_set(data.ravel()); im.filepath_raw=OUT+'/'+name+'.png'; im.file_format='PNG'; im.save(); im.pack(); return im
ai=save_tex('flashlight_albedo',al); oi=save_tex('flashlight_orm',orm,True); ni=save_tex('flashlight_normal',normals,True)
atlas=mat('Weathered utility PBR',(.05,.05,.05),.8,.5)
atlas.use_backface_culling=True
nodes=atlas.node_tree.nodes; links=atlas.node_tree.links; p=nodes.get('Principled BSDF')
a=nodes.new('ShaderNodeTexImage'); a.image=ai; links.new(a.outputs['Color'],p.inputs['Base Color'])
o=nodes.new('ShaderNodeTexImage'); o.image=oi; sep=nodes.new('ShaderNodeSeparateColor'); links.new(o.outputs['Color'],sep.inputs['Color']); links.new(sep.outputs['Green'],p.inputs['Roughness']); links.new(sep.outputs['Blue'],p.inputs['Metallic'])
no=nodes.new('ShaderNodeTexImage'); no.image=ni; nm=nodes.new('ShaderNodeNormalMap'); links.new(no.outputs['Color'],nm.inputs['Color']); links.new(nm.outputs['Normal'],p.inputs['Normal'])
opaque=[]; lenses=[]
for ob in parts:
 if ob.data.materials[0]==glass:
  glass.node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value=0
  glass.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.09
  lenses.append(ob); continue
 old=ob.data.materials[0]; tile=1 if old in (edge,reflector) else 2 if old==rubber else 3 if old==led else 0
 uv=ob.data.uv_layers.active
 for poly in ob.data.polygons:
  coords=[ob.data.vertices[ob.data.loops[li].vertex_index].co for li in poly.loop_indices]
  for li in poly.loop_indices:
   co=ob.data.vertices[ob.data.loops[li].vertex_index].co
   angle=(math.atan2(co.z,co.x)/math.tau)%1
   # Seam vertices use 1 on the final face rather than crossing the whole texture.
   if angle<.00001 and any(c.z<-.00001 for c in coords):angle=1
   vv=max(0,min(1,co.y/.231)) if ob.name=='Body' else float(uv.data[li].uv.y)
   if tile==0 and ob.name!='Body': vv=.70+float(uv.data[li].uv.y)*.295
   uv.data[li].uv=((tile%2)*.5+.004+angle*.492,(tile//2)*.5+.004+vv*.492)
 ob.data.materials.clear(); ob.data.materials.append(atlas); opaque.append(ob)
# Merge geometry, preserve PBR atlas and normals; two draws before shadow pass.
def join_meshes(objects,name):
 bpy.ops.object.select_all(action='DESELECT')
 for ob in objects:ob.select_set(True)
 bpy.context.view_layer.objects.active=objects[0]; bpy.ops.object.join(); ob=objects[0]; ob.name=name
 # One material slot after join, not one slot per original part.
 for poly in ob.data.polygons:poly.material_index=0
 while len(ob.data.materials)>1:ob.data.materials.pop(index=len(ob.data.materials)-1)
 return ob
parts=[join_meshes(opaque,'Flashlight opaque'),join_meshes(lenses,'Lens')]
