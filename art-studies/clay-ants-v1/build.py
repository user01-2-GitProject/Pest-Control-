"""Editable Blender clay ant study. Run: blender -b -t 6 --python build.py"""
import bpy, math
from mathutils import Vector
from pathlib import Path
OUT=Path(__file__).resolve().parent
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def mat(name, color, clay=True):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
 n=m.node_tree.nodes; p=n.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1); p.inputs['Roughness'].default_value=.8
 if clay:
  noise=n.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value=34; noise.inputs['Detail'].default_value=2
  bump=n.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=.16; bump.inputs['Distance'].default_value=.035
  m.node_tree.links.new(noise.outputs['Fac'],bump.inputs['Height']); m.node_tree.links.new(bump.outputs['Normal'],p.inputs['Normal'])
 return m
red=mat('Terracotta clay',(0.43,.065,.027)); darkred=mat('Deep rust clay',(.26,.031,.017))
legmat=mat('Warm joint clay',(.32,.055,.023)); eye=mat('Obsidian clay',(.018,.013,.011),False)
eye.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.3
ivory=mat('Warm cream lettering',(.76,.69,.53),False)
ground=mat('Charcoal olive studio',(.055,.067,.055),False)
pedestal=mat('Earth clay display',(.17,.18,.135))
def ell(name,pos,scale,material):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=16,location=pos)
 o=bpy.context.object; o.name=name; o.scale=scale; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.data.materials.append(material)
 for f in o.data.polygons:f.use_smooth=True
 return o
def limb(name,pts,radii,material):
 # Tapered smooth tube mesh, built around each path point.
 verts=[]; faces=[]; sides=10
 for i,p in enumerate(pts):
  p=Vector(p); tangent=Vector(pts[min(i+1,len(pts)-1)])-Vector(pts[max(i-1,0)])
  tangent.normalize(); axis=tangent.cross(Vector((0,0,1)))
  if axis.length<.01:axis=tangent.cross(Vector((0,1,0)))
  axis.normalize(); other=tangent.cross(axis).normalized()
  for j in range(sides):
   v=p+radii[i]*(axis*math.cos(j*math.tau/sides)+other*math.sin(j*math.tau/sides)); verts.append(v)
 for i in range(len(pts)-1):
  for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
 faces.extend([tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+j for j in range(sides))])
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
 o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);o.data.materials.append(material)
 for f in mesh.polygons:f.use_smooth=True
 bevel=o.modifiers.new('Soft hand-formed joints','BEVEL');bevel.width=.035;bevel.segments=2
 return o
def ant(kind,x):
 soldier=kind=='SOLDIER'; before=set(bpy.data.objects)
 def pt(a):return (a[0]+x,a[1],a[2]+.18)
 def e(name,p,s,m=red):return ell(kind+' '+name,pt(p),s,m)
 e('gaster',(0,1.03,.91),(.48 if soldier else .42,.75,.47),darkred if soldier else red)
 e('petiole rear',(0,.35,.91),(.17,.19,.21))
 e('petiole front',(0,.09,.96),(.15,.18,.22))
 e('thorax',(0,-.35,1.02),(.32,.5,.31))
 e('neck',(0,-.83,1.06),(.18,.18,.17))
 hs=(.59,.55,.43) if soldier else (.36,.43,.33)
 e('head',(0,-1.15,1.1),hs,darkred if soldier else red)
 for side in [-1,1]:
  e('eye',(side*hs[0]*.83,-1.30,1.27),(.105,.115,.115),eye)
  # Three pairs, all originate on thorax, with articulated knees and feet.
  for j,(rooty,kneey,footy) in enumerate([(-.65,-1.0,-1.48),(-.32,-.2,-.12),(-.02,.58,1.06)]):
   reach=1.15 if soldier else 1.0
   pts=[(side*.23,rooty,1.0),(side*.59,kneey,.99),(side*reach,footy,.15),(side*(reach+.14),footy-.13,.10)]
   limb(kind+' leg '+str(side)+' '+str(j),[pt(p) for p in pts],[.085,.07,.036,.012],legmat)
   e('knee',(side*.59,kneey,.99),(.088,.088,.088),legmat)
  limb(kind+' elbowed antenna '+str(side),[pt(p) for p in [(side*.18,-1.51,1.28),(side*.31,-1.9,1.55),(side*.70,-2.13,1.45),(side*.78,-2.27,1.40)]],[.047,.043,.028,.015],red)
  spread=.37 if soldier else .23; length=.57 if soldier else .29
  limb(kind+' mandible '+str(side),[pt(p) for p in [(side*spread,-1.53,1.02),(side*(spread+.12),-1.73,1.00),(side*.18,-1.73-length,.98),(side*.075,-1.61-length,.99)]],[.14 if soldier else .075,.12 if soldier else .065,.06,.008],darkred)
 objs=list(set(bpy.data.objects)-before)
 col=bpy.data.collections.new(kind);bpy.context.scene.collection.children.link(col)
 for o in objs:
  for c in list(o.users_collection):c.objects.unlink(o)
  col.objects.link(o)
 return objs
worker=ant('WORKER',-2.25);soldier=ant('SOLDIER',2.25)
# Export plain geometry/material blockouts individually; procedural clay bump is Blender-only.
for name,objs in [('worker',worker),('soldier',soldier)]:
 bpy.ops.object.select_all(action='DESELECT')
 for o in objs:o.select_set(True)
 # Shift temporarily to asset origin.
 dx=-2.25 if name=='worker' else 2.25
 for o in objs:o.location.x-=dx
 bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'-study.glb')),use_selection=True,export_format='GLB')
 for o in objs:o.location.x+=dx
for x in [-2.25,2.25]:
 bpy.ops.mesh.primitive_cylinder_add(vertices=96,radius=1.95,depth=.18,location=(x,0,0))
 o=bpy.context.object;o.name='Display plinth';o.data.materials.append(pedestal)
 bevel=o.modifiers.new('Rounded clay edge','BEVEL');bevel.width=.09;bevel.segments=3
for txt,x in [('WORKER',-2.25),('SOLDIER',2.25)]:
 bpy.ops.object.text_add(location=(x,-2.48,.01))
 o=bpy.context.object;o.data.body=txt;o.data.align_x='CENTER';o.data.size=.32;o.data.extrude=.001;o.data.materials.append(ivory)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.12));bpy.context.object.data.materials.append(ground)
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(6,-10,12))
cam=bpy.context.object;aim(cam,(0,-.15,.4));cam.data.type='ORTHO';cam.data.ortho_scale=11.6;bpy.context.scene.camera=cam
for name,loc,power,size,color in [('Key',(-3,-4,8),1400,7,(1,.84,.68)),('Fill',(5,-1,6),1000,6,(.76,.85,1)),('Rim',(1,5,7),1500,5,(1,.65,.4))]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.data.color=color;aim(o,(0,0,0))
sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=48;sc.cycles.use_denoising=True
sc.world.color=(.17,.17,.17);sc.render.resolution_x=1600;sc.render.resolution_y=1000;sc.render.resolution_percentage=100
sc.view_settings.view_transform='AgX'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'clay-ant-study.blend'))
sc.render.filepath=str(OUT/'clay-ant-study.png');bpy.ops.render.render(write_still=True)
# Higher game-like angle, deliberately farther away, no camera blur.
cam.location=(0,-8,15);aim(cam,(0,0,0));cam.data.ortho_scale=16
sc.render.filepath=str(OUT/'clay-ant-scale-check.png');bpy.ops.render.render(write_still=True)
print('CLAY_STUDY_COMPLETE')
