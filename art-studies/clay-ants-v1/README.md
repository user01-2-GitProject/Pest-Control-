# Clay ant study v1 — Codex

Status: first static shape/material study awaiting Jimmy's visual feedback. Not a finished game asset.

## Scope and ownership

Codex owns the new files under art-studies/clay-ants-v1 on branch codex/clay-ant-study.
No game scripts, existing art, or Claude's PR #10 files are changed. COORDINATION.md is being updated in Claude's open PR, so this scoped note records the claim without overlapping that file.

## Deliverables

- build.py: reproducible Blender 5.2 script.
- clay-ant-study.blend: editable worker, soldier, studio lighting and camera.
- clay-ant-study.png: close-up comparison.
- clay-ant-scale-check.png: more distant high-angle comparison; not the actual Godot camera.
- worker-study.glb and soldier-study.glb: individual static geometry exports centered separately.

The worker is lean with small mandibles; the soldier has a broader head and heavier mandibles. Both have six legs attached to the thorax, elbowed antennae, petiole nodes, and a distinct gaster.

## Deliberate limits

This is a shape approval checkpoint: no rig, gait, attack animation, baked textures, LODs, collision setup, or runtime replacement yet. The procedural clay bump belongs to the Blender material and does not automatically survive GLB export. Exported basic colors/materials are only a starting point. Meshes are separate editable parts, not draw-call optimized. Unit scale, orientation and silhouettes must be verified in Godot before integration.

## Rebuild

Run from this folder:
    ALSOFT_DRIVERS=null blender -b -t 6 -noaudio --python build.py

## Change journal — 2026-10-15

First worker/soldier clay study created from actual meshes, with two comparison renders. Await visual judgment before animation or refinement. No final asset acceptance or engine performance claims.
