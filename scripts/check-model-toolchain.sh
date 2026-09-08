#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'Model toolchain check failed: %s\n' "$1" >&2
  exit 1
}

command -v blender >/dev/null || fail 'Blender is not installed.'
[[ -x /usr/lib/qt6/bin/balsam ]] || fail 'Qt Quick 3D Balsam is not installed.'

blender_version=$(blender --version 2>/dev/null)
[[ $blender_version == Blender\ 5.2.* ]] || fail 'Blender 5.2 is required.'

qt_package=$(pacman -Q qt6-quick3d 2>/dev/null) || fail 'qt6-quick3d is not installed.'
[[ $qt_package == 'qt6-quick3d 6.11.2-1' ]] || fail "Expected qt6-quick3d 6.11.2-1, found $qt_package."

assimp_package=$(pacman -Q assimp 2>/dev/null) || fail 'Assimp is required by the Balsam importer.'
[[ $assimp_package == assimp\ 6.* ]] || fail "Assimp 6 is required, found $assimp_package."
[[ -e /usr/lib/libassimp.so.6 ]] || fail 'Balsam cannot load libassimp.so.6.'

importer=/usr/lib/qt6/plugins/assetimporters/libassimp.so
[[ -r $importer ]] || fail 'The Balsam Assimp importer is unavailable.'
ldd_output=$(/usr/bin/ldd "$importer" 2>&1) || fail 'The Balsam Assimp importer could not be inspected.'
if [[ $ldd_output == *'not found'* ]]; then
  fail 'The Balsam Assimp importer has unresolved libraries.'
fi

probe_root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-gamepads-model-toolchain.XXXXXX")
trap 'rm -rf -- "$probe_root"' EXIT
mkdir "$probe_root/output"
export MODEL_TOOLCHAIN_PROBE_GLB="$probe_root/probe.glb"

blender --background --factory-startup --disable-autoexec --python-exit-code 1 \
  --python-expr 'import bpy, cattrs, os; assert bpy.app.version[:2] == (5, 2); bpy.ops.mesh.primitive_cube_add(); bpy.ops.export_scene.gltf(filepath=os.environ["MODEL_TOOLCHAIN_PROBE_GLB"], export_format="GLB", export_yup=True, export_animations=False, export_cameras=False, export_lights=False, export_tangents=False, export_extras=False, export_apply=False)' >/dev/null \
  || fail 'Blender headless Python validation failed.'

/usr/lib/qt6/bin/balsam --outputPath "$probe_root/output" "$probe_root/probe.glb" >/dev/null \
  || fail 'Balsam could not convert the Blender GLB probe.'
shopt -s nullglob
probe_meshes=("$probe_root/output/meshes/"*.mesh)
((${#probe_meshes[@]} > 0)) || fail 'Balsam produced no runtime mesh.'
[[ -s $probe_root/output/Probe.qml ]] || fail 'Balsam produced no scene mapping for the probe.'

printf 'Model toolchain ready: %s; %s; %s.\n' \
  "${blender_version%%$'\n'*}" "$qt_package" "$assimp_package"
