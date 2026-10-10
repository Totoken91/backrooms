#!/bin/sh
# Game vs Cycles light measurement for one view: tools/measure-gi.sh view [tag]
# Needs GODOT and BLENDER in the environment, captures in ../backrooms-captures.
VIEW=${1:-reveal}; TAG=${2:-m}; C=../backrooms-captures
PARAMS='{"view":"'$VIEW'","wall_tint":[0.95,1.0,0.7],"floor_tint":[0.84,0.86,0.72],"ceiling_tint":[1.1,1.1,1.05],"exposure":0.35,"panel_color":[1.0,0.97,0.9],"panel_strength":12,"samples":64,"width":360,"height":270,"passes":true}'
[ -f $C/passes-$VIEW-passes.json ] && [ -z "$RECYCLES" ] || "$BLENDER" --background --factory-startup --python tools/blender/render_scene.py -- $C/scene-s2b.json $C/passes-$VIEW.png "$PARAMS" > /dev/null 2>&1
for v in 8 9; do "$GODOT" --path . --resolution 720x540 -- seed=2 shots=$VIEW out=$C tag=-$TAG$v tune=debug_view:$v raw 2>&1 | grep -i "error"; done
node tools/measure-gi.cjs $C/godot-s2-$VIEW-${TAG}8.png $C/godot-s2-$VIEW-${TAG}9.png $C/passes-$VIEW-passes.json
