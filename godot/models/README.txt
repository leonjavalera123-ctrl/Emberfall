Blender .glb models drop in here (exported via BlenderMCP, same pipeline as
Faction Wars). The game uses them automatically when present, otherwise it
falls back to the procedural placeholder buildings.

Expected filenames (Phase 1+):
  hq_karvath.glb    Karvath Command Post (riveted iron hall, smokestack)
  hq_ashfall.glb    Ashfall Command Post (scrap shack, sandbags)
  hq_aurelia.glb    Aurelian Command Post (brass, mooring mast)   [later]
  hq_luminar.glb    Luminar Command Post (white panels, arc coils) [later]

Export from Blender:
  bpy.ops.export_scene.gltf(filepath=..., export_format='GLB',
                            use_selection=True, export_apply=True)
Blender +Y front -> Godot -Z forward. 1 Blender unit = 1 meter (1 tile = 2 m).
