from pathlib import Path
s=Path('work/build_flashlight.py').read_text()
start=s.index("lathe('Body'"); end=s.index("root=bpy.data.objects.new",start)
geometry='''
# Maglite-inspired 2D proportions: 232 mm length, 38 mm barrel, 57 mm head.
lathe('Body',[(0,0),(0,.0175),(.002,.019),(.027,.019),(.030,.0188),(.142,.0188),(.146,.019),(.166,.019),(.170,.018),(.170,0)],body)
lathe('Tail cap',[(-.004,0),(-.004,.015),(-.002,.0188),(0,.0194),(.018,.0194),(.020,.0188)],body)
lathe('Head',[(.162,.0189),(.166,.0198),(.171,.0215),(.179,.0247),(.189,.0273),(.199,.0285),(.218,.0285),(.225,.0284),(.228,.0278),(.229,.0267),(.227,.0259),(.220,.0259),(.204,.021),(.191,.008),(.190,.005)],body)
for y,r in [(.018,.0195),(.030,.019),(.143,.019),(.164,.0198),(.218,.0286)]:
 lathe('Machining seam',[(y-.0004,r-.0003),(y,r),(y+.0004,r-.0003)],body)
lathe('Reflector bowl',[(.225,.0258),(.221,.0253),(.216,.0235),(.210,.0207),(.204,.0166),(.198,.0115),(.194,.006),(.194,.003)],reflector)
lathe('Bulb socket',[(.194,0),(.194,.0035),(.197,.0035),(.197,0)],edge)
lathe('Bulb',[(.197,0),(.197,.002),(.200,.0025),(.203,.0018),(.204,0)],led)
lathe('Lens',[(.2265,0),(.2265,.0258),(.2268,.0258),(.2268,0)],glass)
for name,r,depth,z,material in [('Switch gasket',.0068,.0018,.0188,rubber),('Switch',.0058,.002,.0202,rubber)]:
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=8,radius=1,location=(0,.155,z))
 ob=bpy.context.object; ob.name=name; ob.scale=(r,r,depth); ob.data.materials.append(material); parts.append(ob)
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for p in ob.data.polygons:p.use_smooth=True
'''
s=s[:start]+geometry+Path('work/texture_v3.py').read_text()+'\n'+s[end:]
s=s.replace("OUT=os.path.abspath('outputs/flashlight')","OUT=os.path.abspath('outputs/flashlight_v3'); os.makedirs(OUT+'/source',exist_ok=True)")
s=s.replace('segments=64','segments=48').replace("OUT+'/flashlight.blend'","OUT+'/source/flashlight.blend'")
s=s.replace("glass.diffuse_color=(.19,.27,.25,.14)","glass.diffuse_color=(.8,.84,.82,.055)")
s=s.replace("default_value=.14","default_value=.055")
s=s.replace("s.cycles.samples=48","s.cycles.samples=80; s.cycles.use_denoising=True")
s=s.replace("area((.15,.12,.35),18,.25)","area((.15,.12,.35),12,.25)")
s=s.replace("s.render.filepath=OUT+'/preview.png'","s.render.filepath=OUT+'/preview.png'; s.view_settings.view_transform='AgX'")
exec(compile(s,'flashlight_v3','exec'))
