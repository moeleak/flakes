#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
uploader="${HYDRA_R2_UPLOADER_SCRIPT:-$script_dir/hydra-r2-uploader.sh}"
test_dir="$(mktemp -d)"
log="$test_dir/uploader.log"
cleanup() {
  status=$?
  if ((status != 0)) && [[ -f "$log" ]]; then
    cat "$log" >&2
  fi
  rm -rf -- "$test_dir"
  exit "$status"
}
trap cleanup EXIT

bucket_dir="$test_dir/bucket"
state_dir="$test_dir/state"
hydra_roots="$test_dir/hydra-roots"
pending_roots="$test_dir/pending-roots"
signing_key="$test_dir/signing-key"
mkdir -p "$bucket_dir/nar" "$state_dir" "$hydra_roots" "$pending_roots"
printf 'cache.test-1:not-a-real-key\n' >"$signing_key"

upstream_hash="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
existing_hash="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
new_hash="cccccccccccccccccccccccccccccccc"
root_hash="dddddddddddddddddddddddddddddddd"
oversized_hash="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
blocked_hash="ffffffffffffffffffffffffffffffff"
expired_hash="oooooooooooooooooooooooooooooooo"

upstream_path="/nix/store/$upstream_hash-upstream"
existing_path="/nix/store/$existing_hash-existing"
new_path="/nix/store/$new_hash-new"
root_path="/nix/store/$root_hash-root"
oversized_path="/nix/store/$oversized_hash-oversized"
blocked_path="/nix/store/$blocked_hash-blocked"
expired_path="/nix/store/$expired_hash-expired"

touch "$hydra_roots/${root_path##*/}" "$hydra_roots/${blocked_path##*/}"
touch "$pending_roots/${expired_path##*/}"

printf '%s\n' \
  "StorePath: $existing_path" \
  'URL: nar/existing.nar.zst' \
  "References: ${upstream_path##*/}" \
  >"$bucket_dir/$existing_hash.narinfo"
printf '{}\n' >"$bucket_dir/$existing_hash.ls"
head -c 128 /dev/zero >"$bucket_dir/nar/existing.nar.zst"

printf '%s\n' \
  "StorePath: $expired_path" \
  'URL: nar/expired.nar.zst' \
  'References:' \
  >"$bucket_dir/$expired_hash.narinfo"
printf '{}\n' >"$bucket_dir/$expired_hash.ls"
head -c 900 /dev/zero >"$bucket_dir/nar/expired.nar.zst"
printf 'StoreDir: /nix/store\n' >"$bucket_dir/nix-cache-info"

export TEST_BUCKET_DIR="$bucket_dir"
export TEST_UPSTREAM_HASH="$upstream_hash"
export TEST_UPSTREAM_PATH="$upstream_path"
export TEST_EXISTING_PATH="$existing_path"
export TEST_NEW_PATH="$new_path"
export TEST_ROOT_PATH="$root_path"
export TEST_OVERSIZED_PATH="$oversized_path"
export TEST_BLOCKED_PATH="$blocked_path"

aws() {
  if [[ "$1" == '--endpoint-url' ]]; then
    shift 2
  fi

  if [[ "$1" == 's3api' && "$2" == 'list-objects-v2' ]]; then
    find "$TEST_BUCKET_DIR" -type f -printf '%P\t%s\n' \
      | jq -Rn '{Contents: [inputs | split("\t") | {Key: .[0], Size: (.[1] | tonumber)}]}'
    return
  fi

  if [[ "$1" == 's3' && "$2" == 'sync' ]]; then
    destination="$4"
    find "$destination" -maxdepth 1 -type f -name '*.narinfo' -delete
    while IFS= read -r source; do
      cp -- "$source" "$destination/"
    done < <(find "$TEST_BUCKET_DIR" -maxdepth 1 -type f -name '*.narinfo')
    return
  fi

  if [[ "$1" == 's3api' && "$2" == 'delete-objects' ]]; then
    request=''
    while (($# > 0)); do
      if [[ "$1" == '--delete' ]]; then
        request="${2#file://}"
        break
      fi
      shift
    done
    while IFS= read -r key; do
      rm -f -- "$TEST_BUCKET_DIR/$key"
    done < <(jq -r '.Objects[].Key' "$request")
    printf '{}\n'
    return
  fi

  if [[ "$1" == 's3' && "$2" == 'cp' ]]; then
    source="$3"
    key="${4#s3://*/}"
    mkdir -p "$(dirname -- "$TEST_BUCKET_DIR/$key")"
    cp -- "$source" "$TEST_BUCKET_DIR/$key"
    return
  fi

  printf 'Unexpected aws invocation: %q ' "$@" >&2
  printf '\n' >&2
  return 1
}

curl() {
  output=''
  url=''
  while (($# > 0)); do
    case "$1" in
      --output)
        output="$2"
        shift 2
        ;;
      http*)
        url="$1"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ "$url" == *"/$TEST_UPSTREAM_HASH.narinfo" ]]; then
    printf '%s\n' \
      "StorePath: $TEST_UPSTREAM_PATH" \
      'URL: nar/upstream.nar.xz' \
      'References:' \
      >"$output"
    printf '200'
  else
    : >"$output"
    printf '404'
  fi
}
export -f curl

nix-store() {
  if [[ "$1" == '--check-validity' ]]; then
    return 0
  fi

  if [[ "$1" == '--query' && "$2" == '--requisites' ]]; then
    printf '%s\n' \
      "$TEST_UPSTREAM_PATH" \
      "$TEST_EXISTING_PATH" \
      "$TEST_OVERSIZED_PATH" \
      "$TEST_NEW_PATH" \
      "$TEST_ROOT_PATH" \
      "$TEST_BLOCKED_PATH"
    return
  fi

  if [[ "$1" == '--query' && "$2" == '--references' ]]; then
    case "${3##*/}" in
      "$TEST_EXISTING_PATH"|"${TEST_EXISTING_PATH##*/}")
        printf '%s\n' "$TEST_UPSTREAM_PATH"
        ;;
      "$TEST_OVERSIZED_PATH"|"${TEST_OVERSIZED_PATH##*/}")
        printf '%s\n' "$TEST_UPSTREAM_PATH"
        ;;
      "$TEST_NEW_PATH"|"${TEST_NEW_PATH##*/}")
        printf '%s\n' "$TEST_UPSTREAM_PATH"
        ;;
      "$TEST_ROOT_PATH"|"${TEST_ROOT_PATH##*/}")
        printf '%s\n' "$TEST_EXISTING_PATH" "$TEST_NEW_PATH"
        ;;
      "$TEST_BLOCKED_PATH"|"${TEST_BLOCKED_PATH##*/}")
        printf '%s\n' "$TEST_OVERSIZED_PATH"
        ;;
    esac
    return
  fi

  printf 'Unexpected nix-store invocation: %q ' "$@" >&2
  printf '\n' >&2
  return 1
}

nix() {
  if [[ "$1" != 'copy' ]]; then
    printf 'Unexpected nix invocation: %q ' "$@" >&2
    printf '\n' >&2
    return 1
  fi

  destination=''
  path="${!#}"
  while (($# > 0)); do
    if [[ "$1" == '--to' ]]; then
      destination="${2#file://}"
      destination="${destination%%\?*}"
      break
    fi
    shift
  done

  base="${path##*/}"
  hash="${base%%-*}"
  nar_url="nar/$hash.nar.zst"
  mkdir -p "$destination/nar"
  if [[ "$path" == "$TEST_OVERSIZED_PATH" ]]; then
    head -c 2000 /dev/zero >"$destination/$nar_url"
  else
    head -c 96 /dev/zero >"$destination/$nar_url"
  fi
  printf '%s\n' \
    "StorePath: $path" \
    "URL: $nar_url" \
    'References:' \
    >"$destination/$hash.narinfo"
  printf '{}\n' >"$destination/$hash.ls"
}

export STATE_DIRECTORY="$state_dir"
export R2_BUCKET='nix-cache'
export R2_ENDPOINT='https://example.invalid'
export R2_SIGNING_KEY="$signing_key"
export R2_STORAGE_LIMIT_BYTES=1500
export R2_UPSTREAM_CACHES='https://cache.test https://devenv.test'
export R2_UPSTREAM_MISS_TTL_SECONDS=1209600
export R2_PENDING_ROOTS="$pending_roots"
export HYDRA_GC_ROOTS="$hydra_roots"

# Source the uploader so its external commands resolve to the fixture functions.
# shellcheck disable=SC1090
(source "$uploader") >"$log" 2>&1

test ! -e "$bucket_dir/$expired_hash.narinfo"
test ! -e "$bucket_dir/$expired_hash.ls"
test ! -e "$bucket_dir/nar/expired.nar.zst"
test -e "$bucket_dir/$upstream_hash.narinfo"
test -e "$bucket_dir/$existing_hash.narinfo"
test -e "$bucket_dir/$new_hash.narinfo"
test -e "$bucket_dir/$root_hash.narinfo"
test ! -e "$bucket_dir/$oversized_hash.narinfo"
test ! -e "$bucket_dir/$blocked_hash.narinfo"
test ! -e "$pending_roots/${expired_path##*/}"
test -e "$pending_roots/${oversized_path##*/}"
test -e "$pending_roots/${blocked_path##*/}"

bucket_bytes="$(find "$bucket_dir" -type f -printf '%s\n' | awk '{ total += $1 } END { print total + 0 }')"
((bucket_bytes <= R2_STORAGE_LIMIT_BYTES))

grep -q 'Removed 1 expired pending roots' "$log"
grep -q 'Expired 1 old cache paths' "$log"
grep -q 'Skipped 1 oversized paths and 1 paths with unavailable references' "$log"
grep -q 'Uploaded 2 custom paths; 2 custom paths remain pending' "$log"

printf 'hydra-r2-uploader rolling-cache test passed\n'
