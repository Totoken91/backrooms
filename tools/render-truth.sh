#!/bin/sh
# Cycles ground truth for the QA views: beauty renders (truth-<tag>-<view>.png)
# and diffuse passes (passes-<tag>-<view>-passes.json) from a scene export.
# Usage: tools/render-truth.sh scene.json tag [views...]
BLENDER=${BLENDER:-"C:/Program Files/Blender Foundation/Blender 4.2/blender.exe"}
C=$(cd ../backrooms-captures && pwd -W 2>/dev/null || pwd)
SCENE=$1; TAG=$2; shift 2
VIEWS=${*:-entry reveal interior east}
COMMON='"wall_tint":[0.95,1.0,0.7],"floor_tint":[0.84,0.86,0.72],"ceiling_tint":[1.1,1.1,1.05],"exposure":0.35,"panel_color":[1.0,0.97,0.9],"panel_strength":12'
for v in $VIEWS; do
  "$BLENDER" --background --factory-startup --python tools/blender/render_scene.py -- "$SCENE" "$C/truth-$TAG-$v.png" "{\"view\":\"$v\",$COMMON,\"samples\":128,\"width\":720,\"height\":540}" 2>&1 | grep -E "rendered|Error" | grep -v "Not freed"
  "$BLENDER" --background --factory-startup --python tools/blender/render_scene.py -- "$SCENE" "$C/passes-$TAG-$v.png" "{\"view\":\"$v\",$COMMON,\"samples\":64,\"width\":360,\"height\":270,\"passes\":true}" 2>&1 | grep -E "^passes" | cut -c1-60
done
