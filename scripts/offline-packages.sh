#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
# See LICENSE for the full license text.

# Offline SwiftPM support for KeyCmd.
#
# KeyCmd resolves 8 remote packages plus mlx-swift's two C++ submodules. GitHub
# connectivity from this network is slow enough that those clones fail
# repeatedly, which aborts package resolution before compilation starts. The
# mirror in .offline-packages/mirror lets git serve every one of those URLs
# locally, by rewriting them with url.<base>.insteadOf at the environment level
# (no repository or global git config is modified).
#
# Usage:
#   scripts/offline-packages.sh verify      # check the mirror covers Package.resolved
#   scripts/offline-packages.sh rules       # show the URL rewrites build applies
#   scripts/offline-packages.sh build       # xcodebuild entirely offline
#   scripts/offline-packages.sh test        # xcodebuild test (KeyCmdUITests), offline
#   scripts/offline-packages.sh refresh     # mirror all 8 packages from GitHub (online)
#   scripts/offline-packages.sh submodules  # re-mirror mlx / mlx-c at their pinned SHA
#   scripts/offline-packages.sh snapshot    # pack the mirror for a teammate or CI
#   scripts/offline-packages.sh restore [src]  # unpack a snapshot
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MIRROR="$ROOT/.offline-packages/mirror"
RESOLVED="$ROOT/KeyCmd.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
SNAPSHOT="$ROOT/.offline-packages/mirror-snapshot.tar.gz"

# mlx-swift's .gitmodules, not listed in Package.resolved.
SUBMODULE_URLS="https://github.com/ml-explore/mlx https://github.com/ml-explore/mlx-c"

# GitHub transfers on this network drop mid-stream; keep retries cheap and
# tolerant rather than aborting on a slow link.
git_env() {
  export GIT_CONFIG_COUNT=4 \
    GIT_CONFIG_KEY_0=http.version GIT_CONFIG_VALUE_0=HTTP/1.1 \
    GIT_CONFIG_KEY_1=http.postBuffer GIT_CONFIG_VALUE_1=1048576000 \
    GIT_CONFIG_KEY_2=http.lowSpeedLimit GIT_CONFIG_VALUE_2=0 \
    GIT_CONFIG_KEY_3=http.lowSpeedTime GIT_CONFIG_VALUE_3=999999
}

mirror_name() { # url -> mirror directory name
  local base=${1##*/}
  echo "${base%.git}.git"
}

# Each pin lists "location" before its "revision", so pair them positionally.
pins() {
  awk '/"location"/ { sub(/.*: "/, ""); gsub(/".*/, ""); url = $0 }
       /"revision"/ { sub(/.*: "/, ""); gsub(/".*/, ""); print url " " $0 }' "$RESOLVED"
}

retry_clone() { # url dest attempts
  local url=$1 dest=$2 n=${3:-8} i
  for ((i = 1; i <= n; i++)); do
    rm -rf "$dest.tmp"
    if git clone --bare "$url" "$dest.tmp" >/dev/null 2>&1 \
       && git -C "$dest.tmp" rev-list -n1 --all >/dev/null 2>&1; then
      git -C "$dest.tmp" config --replace-all remote.origin.fetch '+refs/*:refs/*'
      rm -rf "$dest" && mv "$dest.tmp" "$dest" && return 0
    fi
    echo "  attempt $i/$n failed for $url" >&2
    sleep 3
  done
  return 1
}

cmd_verify() {
  if [ ! -d "$MIRROR" ]; then
    echo "no mirror at $MIRROR -- run: scripts/offline-packages.sh refresh (needs GitHub)" >&2
    return 1
  fi
  local missing=0 url name rev
  while read -r url rev; do
    [ -n "$url" ] || continue
    name=$(mirror_name "$url")
    if [ ! -d "$MIRROR/$name" ]; then
      echo "MISSING repo  $name"
      missing=1
    elif ! git -C "$MIRROR/$name" cat-file -e "${rev}^{commit}" 2>/dev/null; then
      echo "MISSING rev   $name @ $rev"
      missing=1
    else
      printf 'ok            %s\n' "$name"
    fi
  done < <(pins)
  for url in $SUBMODULE_URLS; do
    name=$(mirror_name "$url")
    if [ -d "$MIRROR/$name" ]; then
      printf 'ok            %s (shallow)\n' "$name"
    else
      echo "MISSING repo  $name"
      missing=1
    fi
  done
  return $missing
}

cmd_refresh() {
  git_env
  mkdir -p "$MIRROR"
  local url rev name bad=0
  while read -r url rev; do
    [ -n "$url" ] || continue
    name=$(mirror_name "$url")
    if [ -d "$MIRROR/$name" ]; then
      echo "fetching  $name"
      git -C "$MIRROR/$name" fetch --prune origin '+refs/*:refs/*' >/dev/null 2>&1 \
        || echo "  fetch failed (kept existing copy)" >&2
    else
      echo "cloning   $name"
      retry_clone "$url" "$MIRROR/$name" 8 || bad=1
    fi
    git -C "$MIRROR/$name" cat-file -e "${rev}^{commit}" 2>/dev/null \
      || echo "  WARNING: pinned $rev not present in $name after refresh" >&2
  done < <(pins)
  cmd_submodules || bad=1
  return $bad
}

# mlx-swift's C++ submodules are pinned by commit inside mlx-swift, so both the SHA
# and the URL are read back from the mirror instead of hardcoded. Mirroring them
# shallow keeps each at ~3 MB rather than the 72 MB full history.
cmd_submodules() {
  git_env
  mkdir -p "$MIRROR"
  local rev entries urls upath uurl name sha url ok bad=0 i
  rev=$(pins | awk '$1 ~ /mlx-swift$/ { print $2; exit }')
  if [ -z "$rev" ]; then echo "no mlx-swift pin in Package.resolved" >&2; return 1; fi
  if [ ! -d "$MIRROR/mlx-swift.git" ]; then
    echo "mirror/mlx-swift.git missing -- run refresh for the packages first" >&2
    return 1
  fi
  entries=$(git -C "$MIRROR/mlx-swift.git" ls-tree "$rev" Source/Cmlx/ \
            | awk '$2 == "commit" { sub("Source/Cmlx/", "", $4); print $4 " " $3 }')
  urls=$(git -C "$MIRROR/mlx-swift.git" show "$rev:.gitmodules" \
         | awk '/path = / { p = $3 } /url = / { print p " " $3 }')
  while read -r name sha; do
    [ -n "$name" ] || continue
    url=""
    while read -r upath uurl; do
      if [ "${upath#Source/Cmlx/}" = "$name" ]; then url=$uurl; break; fi
    done <<< "$urls"
    if [ -z "$url" ]; then echo "no .gitmodules url for $name" >&2; bad=1; continue; fi
    echo "shallow-mirroring $name @ $sha"
    ok=""
    for ((i = 1; i <= 8; i++)); do
      rm -rf "$MIRROR/$name.git.tmp"
      git init -q --bare "$MIRROR/$name.git.tmp" 2>/dev/null
      if git -C "$MIRROR/$name.git.tmp" fetch -q --depth 1 "$url" "${sha}:refs/heads/main" >/dev/null 2>&1 \
         && git -C "$MIRROR/$name.git.tmp" cat-file -e "${sha}^{commit}" 2>/dev/null; then
        rm -rf "$MIRROR/$name.git"
        mv "$MIRROR/$name.git.tmp" "$MIRROR/$name.git"
        ok=1
        break
      fi
      echo "  attempt $i/8 failed for $url" >&2
      sleep 3
    done
    [ -n "$ok" ] || { echo "  GAVE UP on $name" >&2; bad=1; }
  done <<< "$entries"
  return $bad
}

# Export the url.insteadOf rewrite set covering every package and submodule.
apply_rewrites() {
  local i=0 url rev name
  local -a keys=() vals=()
  add_config() { keys[$i]="$1"; vals[$i]="$2"; i=$((i + 1)); }
  add_rule() { add_config "url.file://$MIRROR/$1.insteadOf" "$2"; }
  while read -r url rev; do
    [ -n "$url" ] || continue
    name=$(mirror_name "$url")
    add_rule "$name" "$url"
    case $url in *.git) ;; *) add_rule "$name" "$url.git" ;; esac
  done < <(pins)
  for url in $SUBMODULE_URLS; do
    name=$(mirror_name "$url")
    add_rule "$name" "$url"
    case $url in *.git) ;; *) add_rule "$name" "$url.git" ;; esac
  done
  # Submodule URLs arrive at git implicitly, which file:// transport blocks by default.
  add_config "protocol.file.allow" "always"
  REWRITE_COUNT=$i
  REWRITE_KEYS=("${keys[@]}")
  REWRITE_VALS=("${vals[@]}")
  export GIT_CONFIG_COUNT=$i
  local n
  for ((n = 0; n < i; n++)); do
    export "GIT_CONFIG_KEY_$n=${keys[$n]}" "GIT_CONFIG_VALUE_$n=${vals[$n]}"
  done
}

cmd_rules() {
  apply_rewrites
  echo "$REWRITE_COUNT rewrite rules -> $MIRROR"
  local n
  for ((n = 0; n < REWRITE_COUNT; n++)); do
    printf '  %s = %s\n' "${REWRITE_KEYS[$n]}" "${REWRITE_VALS[$n]}"
  done
}

cmd_build() {
  apply_rewrites
  cd "$ROOT" || exit 2
  exec xcodebuild -project KeyCmd.xcodeproj -scheme KeyCmd \
    -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath build/DD build CODE_SIGNING_ALLOWED=NO "$@"
}

# UI tests resolve the same package graph, so they need the identical rewrite.
cmd_test() {
  apply_rewrites
  cd "$ROOT" || exit 2
  exec xcodebuild -project KeyCmd.xcodeproj -scheme KeyCmdUITests \
    -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath build/DD test CODE_SIGNING_ALLOWED=NO "$@"
}

cmd_snapshot() {
  tar -czf "$SNAPSHOT" -C "$(dirname "$MIRROR")" "$(basename "$MIRROR")"
  echo "wrote $SNAPSHOT ($(du -h "$SNAPSHOT" | cut -f1))"
}

cmd_restore() {
  local src=${1:-$SNAPSHOT}
  [ -f "$src" ] || { echo "no snapshot at $src" >&2; return 1; }
  mkdir -p "$ROOT/.offline-packages"
  tar -xzf "$src" -C "$ROOT/.offline-packages"
  echo "restored mirror from $src"
}

case "${1:-}" in
  verify)   shift; cmd_verify "$@" ;;
  rules)    shift; cmd_rules "$@" ;;
  refresh)  shift; cmd_refresh "$@" ;;
  submodules) shift; cmd_submodules "$@" ;;
  build)    shift; cmd_build "$@" ;;
  test)     shift; cmd_test "$@" ;;
  snapshot) shift; cmd_snapshot "$@" ;;
  restore)  shift; cmd_restore "$@" ;;
  *) awk '/^# Usage:/{f=1} f && /^#/{sub(/^# ?/, ""); print; next} f{exit}' "$0"; exit 1 ;;
esac
