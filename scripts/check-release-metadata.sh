#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$repo_root/manifest.json"
readme="$repo_root/README.md"
changelog="$repo_root/CHANGELOG.md"

version=$(/usr/bin/jq -er '.version | select(type == "string")' "$manifest")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'Invalid manifest version: %s\n' "$version" >&2
  exit 1
}

escaped_version=${version//./\\.}
/usr/bin/grep -Eq "^## \\[$escaped_version\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$changelog" || {
  printf 'CHANGELOG.md has no dated release section for %s\n' "$version" >&2
  exit 1
}

canonical_base='https://github.com/lightqv/omarchy-gamepads'
/usr/bin/grep -Fq "[$version]: $canonical_base/releases/tag/v$version" "$changelog" || {
  printf 'CHANGELOG.md has no release link for %s\n' "$version" >&2
  exit 1
}
/usr/bin/grep -Fq "[Unreleased]: $canonical_base/compare/v$version...HEAD" "$changelog" || {
  printf 'CHANGELOG.md has no comparison link after %s\n' "$version" >&2
  exit 1
}

/usr/bin/grep -Fq 'https://github.com/lightqv/omarchy-gamepads.git' "$readme" || {
  printf '%s\n' 'README.md does not use the canonical repository URL' >&2
  exit 1
}
/usr/bin/grep -Fq "Version $version was tested" "$readme" || {
  printf 'README.md tested version does not match %s\n' "$version" >&2
  exit 1
}

if /usr/bin/grep -Fq '<git-url>' "$readme"; then
  printf '%s\n' 'README.md still contains a Git URL placeholder' >&2
  exit 1
fi

for screenshot in details-window.png live-input.png compact-panel.png guided-diagnostic.png; do
  [[ -s "$repo_root/.github/assets/$screenshot" ]] || {
    printf 'Missing release screenshot: %s\n' "$screenshot" >&2
    exit 1
  }
done

[[ -s "$repo_root/preview.png" ]] || {
  printf '%s\n' 'Missing marketplace preview: preview.png' >&2
  exit 1
}

printf 'Release metadata %s is consistent.\n' "$version"
