#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
model_root="$repo_root/models/switch-pro"
blender_bin=$(command -v blender)
bwrap_bin=$(command -v bwrap)
prlimit_bin=$(command -v prlimit)
systemd_run_bin=$(command -v systemd-run)
blender_args=(--background --factory-startup --disable-autoexec --offline-mode --python-exit-code 1)
sandbox_optional=()
[[ ! -d /opt/intel ]] || sandbox_optional=(--ro-bind /opt/intel /opt/intel)
maximum_source_bytes=33554432
maximum_review_bytes=8388608
maximum_checkpoint_bytes=1048576

fail() {
  printf 'Model build failed: %s\n' "$1" >&2
  exit 1
}

regular_file_or_absent() {
  local path=$1
  [[ ! -L $path ]] || fail "refusing symlink target: $path"
  [[ ! -e $path || -f $path ]] || fail "target must be a regular file: $path"
}

bounded_regular_file() {
  local path=$1
  local maximum=$2
  [[ -f $path && ! -L $path ]] || fail "expected a regular file: $path"
  local size
  size=$(stat --format='%s' -- "$path")
  ((size <= maximum)) || fail "file exceeds size limit: $path"
}

for path in "$model_root" "$model_root/source" "$model_root/review" "$model_root/work"; do
  [[ ! -L $path ]] || fail "refusing symlink directory: $path"
done

mkdir -p "$model_root/source" "$model_root/review" "$model_root/work"
lock_path="$model_root/work/.build.lock"
[[ ! -L $lock_path ]] || fail "refusing symlink lock: $lock_path"
exec {lock_fd}>"$lock_path"
flock --nonblock "$lock_fd" || fail 'another model build is already running'

destinations=(
  "$model_root/source/switch-pro.blend"
  "$model_root/review/front.png"
  "$model_root/review/rear.png"
  "$model_root/review/left.png"
  "$model_root/review/right.png"
  "$model_root/review/perspective.png"
  "$model_root/review/perspective-dark.png"
  "$model_root/review/top.png"
  "$model_root/review/bottom.png"
  "$model_root/review/rear-perspective.png"
  "$model_root/review/top-perspective.png"
  "$model_root/review/bottom-perspective.png"
  "$model_root/review/low-side-perspective.png"
  "$model_root/review/low-front-perspective.png"
  "$model_root/review/owned-front.png"
  "$model_root/review/owned-left.png"
  "$model_root/review/owned-right.png"
  "$model_root/review/owned-bottom.png"
  "$model_root/review/owned-inverted-bottom.png"
  "$model_root/review/owned-rear-quarter.png"
  "$model_root/review/owned-silhouettes.png"
  "$model_root/review/silhouette.png"
  "$model_root/review/turntable.png"
  "$model_root/review/turntable.gif"
  "$model_root/review/fit.json"
  "$model_root/review/owned-fit.json"
  "$model_root/checkpoint.json"
)
for path in "${destinations[@]}"; do
  regular_file_or_absent "$path"
done
[[ ! -f $model_root/source/switch-pro.blend ]] \
  || bounded_regular_file "$model_root/source/switch-pro.blend" "$maximum_source_bytes"
[[ ! -f $model_root/checkpoint.json ]] \
  || bounded_regular_file "$model_root/checkpoint.json" "$maximum_checkpoint_bytes"

trusted_inputs=(
  "$model_root/asset-contract.json"
  "$model_root/review-decision.json"
  "$model_root/tools/build_model.py"
  "$model_root/tools/surface_maps.py"
  "$model_root/tools/photo_profiles.py"
  "$model_root/tools/photo_shape_profiles.json"
  "$model_root/tools/owned_photo_landmarks.json"
  "$model_root/tools/owned_photo_cameras.json"
  "$model_root/tools/compare_owned_reference.py"
  "$model_root/tools/reference_landmarks.json"
  "$model_root/tools/reference_front_mask.json"
  "$model_root/tools/compare_reference.py"
  "$model_root/tools/validate_model.py"
  "$model_root/tools/render_review.py"
  "$model_root/tools/iterate_model.py"
  "$model_root/tools/iterate_scene.py"
  "$model_root/tools/compare_photo_views.py"
  "$model_root/tools/test_validator.py"
  "$model_root/tools/write_checkpoint.py"
  "$repo_root/scripts/build-switch-pro-model.sh"
  "$repo_root/scripts/check-model-toolchain.sh"
)
input_snapshot=$(sha256sum -- "${trusted_inputs[@]}")

stage_root=$(mktemp -d "$model_root/work/build.XXXXXX")
stage_home="$stage_root/home"
stage_review="$stage_root/review"
stage_generated="$stage_root/generated.blend"
stage_generated_validation="$stage_root/generated-validation.json"
stage_source="$stage_root/switch-pro.blend"
stage_validation="$stage_root/validation.json"
stage_checkpoint="$stage_root/checkpoint.json"
mkdir "$stage_home" "$stage_review"
promotion_started=false
backups=()
had_destinations=()

cleanup() {
  local status=$?
  local rollback_failed=false
  trap - EXIT
  set +e
  if [[ $promotion_started == true ]]; then
    for index in "${!destinations[@]}"; do
      backup=${backups[$index]}
      destination=${destinations[$index]}
      if [[ ${had_destinations[$index]} == true ]]; then
        mv -fT -- "$backup" "$destination" || rollback_failed=true
      elif [[ -e $destination || -L $destination ]]; then
        rm -f -- "$destination" || rollback_failed=true
      fi
    done
  fi
  rm -rf -- "$stage_root" || rollback_failed=true
  if [[ $rollback_failed == true ]]; then
    printf 'Model build rollback was incomplete.\n' >&2
    status=1
  fi
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT TERM HUP

run_blender() {
  local sandbox_environment=()
  local sandbox_readonly=()
  local seconds=180
  [[ $* != *render_review.py* ]] || seconds=300
  [[ -z ${SWITCH_PRO_TEST_SOURCE_PATH:-} ]] \
    || sandbox_readonly=(--ro-bind "$SWITCH_PRO_TEST_SOURCE_PATH" "$SWITCH_PRO_TEST_SOURCE_PATH")
  local name
  for name in SWITCH_PRO_SOURCE_PATH SWITCH_PRO_REVIEW_ROOT SWITCH_PRO_VALIDATION_PATH SWITCH_PRO_TEST_SOURCE_PATH; do
    [[ -z ${!name:-} ]] || sandbox_environment+=(--setenv "$name" "${!name}")
  done
  "$systemd_run_bin" --user --scope --quiet --collect \
    --property=MemoryMax=4G --property=MemorySwapMax=0 \
    --property=TasksMax=128 --property=CPUQuota=400% -- \
    timeout --signal=TERM --kill-after=15s "$seconds" \
    "$prlimit_bin" --as=4294967296 --nofile=1024 -- \
    "$bwrap_bin" \
      --clearenv \
      --unshare-net \
      --unshare-pid \
      --cap-drop ALL \
      --die-with-parent \
      --new-session \
      --ro-bind /usr /usr \
      --ro-bind /etc /etc \
      "${sandbox_optional[@]}" \
      --ro-bind "$model_root/tools" "$model_root/tools" \
      --ro-bind "$model_root/asset-contract.json" "$model_root/asset-contract.json" \
      --bind "$stage_root" "$stage_root" \
      "${sandbox_readonly[@]}" \
      --dev /dev \
      --proc /proc \
      --tmpfs /tmp \
      --symlink usr/bin /bin \
      --symlink usr/lib /lib \
      --symlink usr/lib /lib64 \
      --setenv HOME "$stage_home" \
      --setenv XDG_CACHE_HOME "$stage_home/.cache" \
      --setenv XDG_CONFIG_HOME "$stage_home/.config" \
      --setenv PYTHONHASHSEED 0 \
      --setenv PATH /usr/bin \
      --setenv LANG C.UTF-8 \
      --setenv ALSOFT_DRIVERS null \
      "${sandbox_environment[@]}" \
      --chdir "$model_root" \
      -- "$blender_bin" "${blender_args[@]}" "$@"
}

ulimit -f 1048576
"$repo_root/scripts/check-model-toolchain.sh"

SWITCH_PRO_SOURCE_PATH="$stage_generated" run_blender \
  --python "$model_root/tools/build_model.py"
bounded_regular_file "$stage_generated" "$maximum_source_bytes"
SWITCH_PRO_VALIDATION_PATH="$stage_generated_validation" run_blender \
  --disable-depsgraph-on-file-load "$stage_generated" \
  --python "$model_root/tools/validate_model.py"

retained=false
if [[ -f $model_root/checkpoint.json && -f $model_root/source/switch-pro.blend ]] \
  && python -c 'import json, sys; old=json.load(open(sys.argv[1], encoding="utf-8")); new=json.load(open(sys.argv[2], encoding="utf-8")); raise SystemExit(old.get("validation", {}).get("sceneSha256") != new.get("sceneSha256"))' \
    "$model_root/checkpoint.json" "$stage_generated_validation"; then
  retained_source="$stage_root/retained.blend"
  retained_validation="$stage_root/retained-validation.json"
  cp --no-dereference --reflink=auto -- "$model_root/source/switch-pro.blend" "$retained_source"
  bounded_regular_file "$retained_source" "$maximum_source_bytes"
  if SWITCH_PRO_VALIDATION_PATH="$retained_validation" run_blender \
    --disable-depsgraph-on-file-load "$retained_source" \
    --python "$model_root/tools/validate_model.py" \
    && python -c 'import json, sys; first=json.load(open(sys.argv[1], encoding="utf-8")); second=json.load(open(sys.argv[2], encoding="utf-8")); raise SystemExit(first["sceneSha256"] != second["sceneSha256"])' \
      "$stage_generated_validation" "$retained_validation"; then
    mv -T -- "$retained_source" "$stage_source"
    mv -T -- "$retained_validation" "$stage_validation"
    retained=true
  fi
fi
if [[ $retained == false ]]; then
  mv -T -- "$stage_generated" "$stage_source"
  mv -T -- "$stage_generated_validation" "$stage_validation"
fi

SWITCH_PRO_REVIEW_ROOT="$stage_review" run_blender "$stage_source" \
  --python "$model_root/tools/render_review.py"
python "$model_root/tools/compare_owned_reference.py" --review "$stage_review"
python "$model_root/tools/compare_reference.py" --review "$stage_review"
bounded_regular_file "$stage_source" "$maximum_source_bytes"
for path in "$stage_review"/*.png; do
  bounded_regular_file "$path" "$maximum_review_bytes"
done
bounded_regular_file "$stage_review/turntable.gif" "$maximum_review_bytes"
bounded_regular_file "$stage_review/fit.json" "$maximum_checkpoint_bytes"
bounded_regular_file "$stage_review/owned-fit.json" "$maximum_checkpoint_bytes"

[[ $(sha256sum -- "${trusted_inputs[@]}") == "$input_snapshot" ]] \
  || fail 'trusted model inputs changed during the build'
python "$model_root/tools/write_checkpoint.py" \
  --source "$stage_source" \
  --review "$stage_review" \
  --validation "$stage_validation" \
  --output "$stage_checkpoint"
bounded_regular_file "$stage_checkpoint" "$maximum_checkpoint_bytes"
[[ $(sha256sum -- "${trusted_inputs[@]}") == "$input_snapshot" ]] \
  || fail 'trusted model inputs changed while writing provenance'

# Reload a read-only staged copy for each adversarial mutation.
test_source_root="$stage_root/test-source"
mkdir "$test_source_root"
cp --no-dereference -- "$stage_source" "$test_source_root/switch-pro.blend"
SWITCH_PRO_TEST_SOURCE_PATH="$test_source_root/switch-pro.blend" run_blender \
  "$stage_source" --python "$model_root/tools/test_validator.py"
[[ $(sha256sum -- "${trusted_inputs[@]}") == "$input_snapshot" ]] \
  || fail 'trusted model inputs changed during adversarial validation'

staged=(
  "$stage_source"
  "$stage_review/front.png"
  "$stage_review/rear.png"
  "$stage_review/left.png"
  "$stage_review/right.png"
  "$stage_review/perspective.png"
  "$stage_review/perspective-dark.png"
  "$stage_review/top.png"
  "$stage_review/bottom.png"
  "$stage_review/rear-perspective.png"
  "$stage_review/top-perspective.png"
  "$stage_review/bottom-perspective.png"
  "$stage_review/low-side-perspective.png"
  "$stage_review/low-front-perspective.png"
  "$stage_review/owned-front.png"
  "$stage_review/owned-left.png"
  "$stage_review/owned-right.png"
  "$stage_review/owned-bottom.png"
  "$stage_review/owned-inverted-bottom.png"
  "$stage_review/owned-rear-quarter.png"
  "$stage_review/owned-silhouettes.png"
  "$stage_review/silhouette.png"
  "$stage_review/turntable.png"
  "$stage_review/turntable.gif"
  "$stage_review/fit.json"
  "$stage_review/owned-fit.json"
  "$stage_checkpoint"
)
backup_root="$stage_root/backup"
mkdir "$backup_root"
for index in "${!destinations[@]}"; do
  backups+=("$backup_root/$index")
done
for index in "${!destinations[@]}"; do
  backup=${backups[$index]}
  destination=${destinations[$index]}
  regular_file_or_absent "$destination"
  if [[ -f $destination ]]; then
    cp -a --no-dereference --reflink=auto -- "$destination" "$backup"
    had_destinations+=(true)
  else
    had_destinations+=(false)
  fi
done
promotion_started=true
for index in "${!destinations[@]}"; do
  regular_file_or_absent "${destinations[$index]}"
  mv -T -- "${staged[$index]}" "${destinations[$index]}"
done
promotion_started=false

printf 'Switch Pro source model and review renders are ready.\n'
