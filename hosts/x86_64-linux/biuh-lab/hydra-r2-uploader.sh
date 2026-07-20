#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

: "${STATE_DIRECTORY:?STATE_DIRECTORY is not set}"
: "${R2_BUCKET:?R2_BUCKET is not set}"
: "${R2_ENDPOINT:?R2_ENDPOINT is not set}"
: "${R2_SIGNING_KEY:?R2_SIGNING_KEY is not set}"
: "${R2_STORAGE_LIMIT_BYTES:?R2_STORAGE_LIMIT_BYTES is not set}"
: "${R2_UPSTREAM_CACHES:?R2_UPSTREAM_CACHES is not set}"
: "${R2_PENDING_ROOTS:?R2_PENDING_ROOTS is not set}"
: "${HYDRA_GC_ROOTS:?HYDRA_GC_ROOTS is not set}"

if [[ ! "$R2_STORAGE_LIMIT_BYTES" =~ ^[0-9]+$ ]] || ((R2_STORAGE_LIMIT_BYTES <= 0)); then
  echo "R2_STORAGE_LIMIT_BYTES must be a positive integer" >&2
  exit 1
fi

upstream_jobs="${R2_UPSTREAM_JOBS:-16}"
if [[ ! "$upstream_jobs" =~ ^[0-9]+$ ]] || ((upstream_jobs <= 0)); then
  echo "R2_UPSTREAM_JOBS must be a positive integer" >&2
  exit 1
fi

IFS=' ' read -r -a upstream_caches <<<"$R2_UPSTREAM_CACHES"
if ((${#upstream_caches[@]} == 0)); then
  echo "No upstream caches are configured" >&2
  exit 1
fi

export AWS_PAGER=""
export HOME="$STATE_DIRECTORY"
export XDG_CACHE_HOME="$STATE_DIRECTORY/cache"
mkdir -p "$XDG_CACHE_HOME"

exec 9>"$STATE_DIRECTORY/uploader.lock"
if ! flock --nonblock 9; then
  echo "Another R2 uploader run is still active; skipping"
  exit 0
fi

work_dir="$(mktemp -d "$STATE_DIRECTORY/run.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT

stage_dir="$work_dir/cache"
inventory_json="$work_dir/inventory.json"
inventory_tsv="$work_dir/inventory.tsv"
roots_file="$work_dir/roots"
desired_file="$work_dir/desired"
remote_narinfo_dir="$STATE_DIRECTORY/remote-narinfos"
upstream_state_dir="$STATE_DIRECTORY/upstream"
mkdir -p "$stage_dir" "$remote_narinfo_dir" "$upstream_state_dir"

aws_r2() {
  aws --endpoint-url "$R2_ENDPOINT" "$@"
}

human_bytes() {
  numfmt --to=iec-i --suffix=B "$1"
}

declare -A remote_size=()
bucket_bytes=0

refresh_inventory() {
  aws_r2 s3api list-objects-v2 \
    --bucket "$R2_BUCKET" \
    --output json >"$inventory_json"

  jq -r '.Contents[]? | [.Key, (.Size | tostring)] | @tsv' \
    "$inventory_json" >"$inventory_tsv"

  remote_size=()
  bucket_bytes=0
  while IFS=$'\t' read -r key size; do
    [[ -n "$key" ]] || continue
    remote_size["$key"]="$size"
    bucket_bytes=$((bucket_bytes + size))
  done <"$inventory_tsv"
}

object_exists() {
  [[ -v "remote_size[$1]" ]]
}

upload_object() {
  local key="$1"
  local source_file="$2"
  local content_type="$3"
  local new_size old_size delta

  new_size="$(stat --format='%s' "$source_file")"
  old_size="${remote_size[$key]:-0}"
  delta=$((new_size - old_size))

  if ((delta > 0 && bucket_bytes + delta > R2_STORAGE_LIMIT_BYTES)); then
    return 75
  fi

  if ! aws_r2 s3 cp \
    "$source_file" "s3://$R2_BUCKET/$key" \
    --content-type "$content_type" \
    --no-progress \
    --only-show-errors; then
    return 1
  fi

  bucket_bytes=$((bucket_bytes + delta))
  remote_size["$key"]="$new_size"
}

queue_batch_delete() {
  local key="$1"
  object_exists "$key" || return 0
  printf '%s\n' "$key" >>"$work_dir/delete-keys"
}

run_batch_deletes() {
  local unique_keys="$work_dir/delete-keys.unique"
  local chunk_dir="$work_dir/delete-chunks"
  local request response key size

  [[ -s "$work_dir/delete-keys" ]] || return 0
  sort -u "$work_dir/delete-keys" >"$unique_keys"
  mkdir -p "$chunk_dir"
  split --lines=1000 --numeric-suffixes=1 --suffix-length=4 \
    "$unique_keys" "$chunk_dir/keys."

  for chunk in "$chunk_dir"/keys.*; do
    request="$chunk.json"
    response="$chunk.response.json"
    jq -Rn '{Objects: [inputs | {Key: .}], Quiet: true}' \
      <"$chunk" >"$request"
    aws_r2 s3api delete-objects \
      --bucket "$R2_BUCKET" \
      --delete "file://$request" \
      --output json >"$response"
    if [[ -s "$response" ]] \
      && ! jq -e '((.Errors // []) | length) == 0' "$response" >/dev/null; then
      echo "R2 returned errors while pruning cache objects" >&2
      jq -c '.Errors' "$response" >&2
      exit 1
    fi

    while IFS= read -r key; do
      object_exists "$key" || continue
      size="${remote_size[$key]}"
      bucket_bytes=$((bucket_bytes - size))
      unset 'remote_size[$key]'
      if [[ "$key" == *.narinfo ]]; then
        rm -f -- "$remote_narinfo_dir/${key##*/}"
      fi
    done <"$chunk"
  done
}

refresh_inventory
echo "R2 currently uses $(human_bytes "$bucket_bytes") of $(human_bytes "$R2_STORAGE_LIMIT_BYTES")"

# Keep a local mirror of the small metadata files. It lets the garbage
# collector determine which content-addressed NAR objects are still referenced.
aws_r2 s3 sync \
  "s3://$R2_BUCKET" "$remote_narinfo_dir" \
  --exclude '*' \
  --include '*.narinfo' \
  --delete \
  --no-progress \
  --only-show-errors

remote_narinfo_count=0
while IFS=$'\t' read -r key _size; do
  [[ "$key" == *.narinfo && "$key" != */* ]] || continue
  ((remote_narinfo_count += 1))
  if [[ ! -f "$remote_narinfo_dir/$key" ]]; then
    echo "The local narinfo mirror is incomplete: $key is missing" >&2
    exit 1
  fi
done <"$inventory_tsv"

local_narinfo_count="$(find "$remote_narinfo_dir" -maxdepth 1 -type f -name '*.narinfo' -printf '.' | wc -c)"
if ((local_narinfo_count != remote_narinfo_count)); then
  echo "The R2 inventory changed while it was being mirrored; retrying next run" >&2
  exit 1
fi

# Hydra and this uploader name every root marker after the corresponding
# /nix/store path. Derivation-only roots are scheduled or failed builds; only
# successful output roots should seed the public binary cache.
find "$R2_PENDING_ROOTS" -mindepth 1 -maxdepth 1 -type f -print0 \
  | while IFS= read -r -d '' marker; do
      path="/nix/store/${marker##*/}"
      if ! nix-store --check-validity "$path" 2>/dev/null; then
        rm -f -- "$marker"
      fi
    done

find "$HYDRA_GC_ROOTS" "$R2_PENDING_ROOTS" -mindepth 1 -maxdepth 1 -printf '%f\n' \
  | while IFS= read -r base; do
      [[ "$base" == *.drv ]] && continue
      path="/nix/store/$base"
      if nix-store --check-validity "$path" 2>/dev/null; then
        printf '%s\n' "$path"
      fi
    done \
  | awk '!seen[$0]++' >"$roots_file"

if [[ ! -s "$roots_file" ]]; then
  echo "Hydra has no valid output roots; refusing to prune or upload" >&2
  exit 1
fi

mapfile -t roots <"$roots_file"
nix-store --query --requisites "${roots[@]}" \
  | awk '!seen[$0]++' >"$desired_file"

if [[ ! -s "$desired_file" ]]; then
  echo "Hydra's retained output closure is empty; refusing to prune" >&2
  exit 1
fi

declare -A desired_path=()
declare -a desired_order=()
while IFS= read -r path; do
  base="${path##*/}"
  hash="${base%%-*}"
  if [[ ! "$path" =~ ^/nix/store/[0-9a-z]{32}-.+ ]]; then
    echo "Unexpected store path in Hydra closure: $path" >&2
    exit 1
  fi
  desired_path["$hash"]="$path"
  desired_order+=("$hash")
done <"$desired_file"

echo "Hydra retains ${#roots[@]} output roots and ${#desired_order[@]} closure paths"

# Protect every candidate from local Nix GC before making network requests.
# Confirmed upstream paths and completed uploads remove their marker later.
for hash in "${desired_order[@]}"; do
  touch "$R2_PENDING_ROOTS/${desired_path[$hash]##*/}"
done

# The upstream filter also covers older objects already present in R2. Keep
# unique remote paths even after they leave the current Hydra closure, while
# allowing old copies that exist upstream to be reclaimed.
declare -A candidate_path=()
declare -a candidate_order=("${desired_order[@]}")
declare -A remote_nar_url=()
for hash in "${desired_order[@]}"; do
  candidate_path["$hash"]="${desired_path[$hash]}"
done

while IFS=$'\t' read -r key _size; do
  [[ "$key" =~ ^([0-9a-z]{32})\.narinfo$ ]] || continue
  hash="${BASH_REMATCH[1]}"
  narinfo="$remote_narinfo_dir/$key"
  store_path="$(sed -n 's/^StorePath: //p' "$narinfo" | head -n 1)"
  if [[ ! "$store_path" =~ ^/nix/store/$hash-.+ ]]; then
    echo "R2 contains an invalid narinfo: $key" >&2
    exit 1
  fi
  nar_url="$(sed -n 's/^URL: //p' "$narinfo" | head -n 1)"
  if [[ -z "$nar_url" ]]; then
    echo "R2 narinfo has no URL: $key" >&2
    exit 1
  fi
  remote_nar_url["$hash"]="$nar_url"
  if [[ ! -v "candidate_path[$hash]" ]]; then
    candidate_path["$hash"]="$store_path"
    candidate_order+=("$hash")
  fi
done <"$inventory_tsv"

# Positive upstream results are immutable because Nix store paths are content
# addressed. Cache them locally; misses are deliberately checked again later.
declare -A upstream_source=()
for index in "${!upstream_caches[@]}"; do
  cache_url="${upstream_caches[$index]%/}"
  cache_state="$upstream_state_dir/$index"
  missing_file="$work_dir/upstream-missing.$index"
  mkdir -p "$cache_state"
  : >"$missing_file"

  for hash in "${candidate_order[@]}"; do
    [[ -v "upstream_source[$hash]" ]] && continue
    cached="$cache_state/$hash.narinfo"
    if [[ -f "$cached" ]] \
      && grep -Eq "^StorePath: /nix/store/$hash-.+" "$cached" \
      && grep -q '^URL: ' "$cached"; then
      upstream_source["$hash"]="$index"
    else
      rm -f -- "$cached"
      printf '%s\n' "$hash" >>"$missing_file"
    fi
  done

  if [[ -s "$missing_file" ]]; then
    export UPSTREAM_CACHE_URL="$cache_url"
    export UPSTREAM_CACHE_STATE="$cache_state"
    # The variables in this worker script must expand in the child shell.
    # shellcheck disable=SC2016
    xargs -r -P "$upstream_jobs" -n 1 bash -c '
      set -euo pipefail
      hash="$1"
      destination="$UPSTREAM_CACHE_STATE/$hash.narinfo"
      temporary="$destination.tmp.$$"
      trap '\''rm -f -- "$temporary"'\'' EXIT

      if ! status="$(curl \
        --silent \
        --show-error \
        --location \
        --retry 3 \
        --retry-all-errors \
        --connect-timeout 10 \
        --max-time 60 \
        --output "$temporary" \
        --write-out "%{http_code}" \
        "$UPSTREAM_CACHE_URL/$hash.narinfo")"; then
        echo "Unable to query $UPSTREAM_CACHE_URL for $hash" >&2
        exit 1
      fi

      case "$status" in
        200)
          if ! grep -Eq "^StorePath: /nix/store/$hash-.+" "$temporary" \
            || ! grep -q "^URL: " "$temporary"; then
            echo "Invalid narinfo returned by $UPSTREAM_CACHE_URL for $hash" >&2
            exit 1
          fi
          mv -- "$temporary" "$destination"
          ;;
        404)
          ;;
        *)
          echo "Unexpected HTTP $status from $UPSTREAM_CACHE_URL for $hash" >&2
          exit 1
          ;;
      esac
    ' _ <"$missing_file"
  fi

  for hash in "${candidate_order[@]}"; do
    [[ -v "upstream_source[$hash]" ]] && continue
    cached="$cache_state/$hash.narinfo"
    if [[ -f "$cached" ]]; then
      upstream_source["$hash"]="$index"
    fi
  done
done

declare -A proxy_file=()
for hash in "${!upstream_source[@]}"; do
  index="${upstream_source[$hash]}"
  cache_url="${upstream_caches[$index]%/}"
  source_narinfo="$upstream_state_dir/$index/$hash.narinfo"
  relative_url="$(sed -n 's/^URL: //p' "$source_narinfo" | head -n 1)"
  if [[ -z "$relative_url" ]]; then
    echo "Upstream narinfo for $hash has no URL" >&2
    exit 1
  fi
  if [[ "$relative_url" =~ ^https?:// ]]; then
    absolute_url="$relative_url"
  else
    absolute_url="$cache_url/${relative_url#/}"
  fi
  proxy="$stage_dir/$hash.narinfo"
  awk -v url="$absolute_url" '
    /^URL: / { print "URL: " url; next }
    { print }
  ' "$source_narinfo" >"$proxy"
  proxy_file["$hash"]="$proxy"
done

desired_upstream_count=0
for hash in "${desired_order[@]}"; do
  if [[ -v "upstream_source[$hash]" ]]; then
    ((desired_upstream_count += 1))
  fi
done
custom_count=$((${#desired_order[@]} - desired_upstream_count))
echo "$desired_upstream_count desired paths are already available upstream; $custom_count paths require this cache"

# Classify every remote narinfo before deleting anything. Relative NARs remain
# stored when their paths are unavailable from every configured upstream.
declare -A remote_custom_valid=()
declare -A keep_nar=()

for hash in "${!remote_nar_url[@]}"; do
  nar_url="${remote_nar_url[$hash]}"
  if [[ ! -v "upstream_source[$hash]" ]] \
    && [[ "$nar_url" == nar/* ]] \
    && object_exists "$nar_url"; then
    remote_custom_valid["$hash"]=1
    keep_nar["$nar_url"]=1
    if [[ -v "desired_path[$hash]" ]]; then
      cp -- "$remote_narinfo_dir/$hash.narinfo" "$stage_dir/$hash.narinfo"
    fi
  fi
done

for hash in "${desired_order[@]}"; do
  if [[ -v "upstream_source[$hash]" ]] || [[ -v "remote_custom_valid[$hash]" ]]; then
    rm -f -- "$R2_PENDING_ROOTS/${desired_path[$hash]##*/}"
  fi
done

# Prune upstream copies, invalid metadata, listings for proxy paths, and every
# orphan NAR that is no longer referenced by a unique remote path.
: >"$work_dir/delete-keys"
proxy_replaced=0
while IFS=$'\t' read -r key _size; do
  if [[ "$key" =~ ^([0-9a-z]{32})\.narinfo$ ]]; then
    hash="${BASH_REMATCH[1]}"
    if [[ -v "upstream_source[$hash]" ]]; then
      if [[ ! -v "desired_path[$hash]" ]] \
        || ! cmp --silent "${proxy_file[$hash]}" "$remote_narinfo_dir/$key"; then
        queue_batch_delete "$key"
        ((proxy_replaced += 1))
      fi
      queue_batch_delete "$hash.ls"
    elif [[ ! -v "remote_custom_valid[$hash]" ]]; then
      queue_batch_delete "$key"
      queue_batch_delete "$hash.ls"
    fi
  elif [[ "$key" =~ ^([0-9a-z]{32})\.ls$ ]]; then
    hash="${BASH_REMATCH[1]}"
    if [[ ! -v "remote_custom_valid[$hash]" ]]; then
      queue_batch_delete "$key"
    fi
  elif [[ "$key" == nar/* ]] && [[ ! -v "keep_nar[$key]" ]]; then
    queue_batch_delete "$key"
  fi
done <"$inventory_tsv"

prune_count="$(sort -u "$work_dir/delete-keys" | sed '/^$/d' | wc -l)"
run_batch_deletes
echo "Removed $proxy_replaced upstream payload narinfos and pruned $prune_count redundant objects"
echo "R2 uses $(human_bytes "$bucket_bytes") after pruning"

# Add proxy metadata that did not previously exist. These files are normally
# under 1 KiB and make cache.leak.moe usable without copying upstream NARs.
proxy_added=0
proxy_deferred=0
for hash in "${desired_order[@]}"; do
  [[ -v "upstream_source[$hash]" ]] || continue
  key="$hash.narinfo"
  object_exists "$key" && continue
  proxy="${proxy_file[$hash]}"
  if upload_object "$key" "$proxy" 'text/x-nix-narinfo'; then
    cp -- "$proxy" "$remote_narinfo_dir/$key"
    ((proxy_added += 1))
  else
    status=$?
    if ((status == 75)); then
      ((proxy_deferred += 1))
    else
      echo "Failed to upload proxy narinfo for $hash" >&2
      exit "$status"
    fi
  fi
done

# A fresh file cache writes this on its first copy. Install it explicitly so a
# proxy-only run still produces a valid binary cache root.
printf 'StoreDir: /nix/store\n' >"$stage_dir/nix-cache-info"
if ! object_exists 'nix-cache-info'; then
  if ! upload_object 'nix-cache-info' "$stage_dir/nix-cache-info" 'text/plain'; then
    echo "R2 has no room for nix-cache-info" >&2
    exit 1
  fi
fi

stage_uri="file://$stage_dir?compression=zstd&parallel-compression=true&write-nar-listing=true&secret-key=$R2_SIGNING_KEY"
uploaded_paths=0
deferred_paths=0

for hash in "${desired_order[@]}"; do
  [[ -v "upstream_source[$hash]" ]] && continue
  [[ -v "remote_custom_valid[$hash]" ]] && continue
  path="${desired_path[$hash]}"

  while IFS= read -r reference; do
    [[ "$reference" == "$path" ]] && continue
    ref_base="${reference##*/}"
    ref_hash="${ref_base%%-*}"
    if [[ ! -f "$stage_dir/$ref_hash.narinfo" ]]; then
      echo "Cannot stage $path: reference $reference has no narinfo" >&2
      exit 1
    fi
  done < <(nix-store --query --references "$path")

  nix copy \
    --no-recursive \
    --no-check-sigs \
    --to "$stage_uri" \
    "$path"

  narinfo="$stage_dir/$hash.narinfo"
  nar_url="$(sed -n 's/^URL: //p' "$narinfo" | head -n 1)"
  if [[ "$nar_url" != nar/* ]] || [[ ! -f "$stage_dir/$nar_url" ]]; then
    echo "Staged narinfo for $path has an invalid NAR URL: $nar_url" >&2
    exit 1
  fi

  candidate_keys=("$nar_url")
  [[ -f "$stage_dir/$hash.ls" ]] && candidate_keys+=("$hash.ls")
  candidate_keys+=("$hash.narinfo")

  planned_growth=0
  for key in "${candidate_keys[@]}"; do
    object_exists "$key" && continue
    size="$(stat --format='%s' "$stage_dir/$key")"
    ((planned_growth += size))
  done

  if ((bucket_bytes + planned_growth > R2_STORAGE_LIMIT_BYTES)); then
    echo "R2 limit reached before $path; leaving it and later paths pending"
    break
  fi

  if ! object_exists "$nar_url"; then
    upload_object "$nar_url" "$stage_dir/$nar_url" 'application/x-nix-nar'
  fi
  if [[ -f "$stage_dir/$hash.ls" ]] && ! object_exists "$hash.ls"; then
    upload_object "$hash.ls" "$stage_dir/$hash.ls" 'application/json'
  fi
  upload_object "$hash.narinfo" "$narinfo" 'text/x-nix-narinfo'
  cp -- "$narinfo" "$remote_narinfo_dir/$hash.narinfo"
  remote_custom_valid["$hash"]=1
  rm -f -- "$R2_PENDING_ROOTS/${path##*/}"
  ((uploaded_paths += 1))
done

deferred_paths=0
for hash in "${desired_order[@]}"; do
  [[ -v "upstream_source[$hash]" ]] && continue
  [[ -v "remote_custom_valid[$hash]" ]] && continue
  ((deferred_paths += 1))
done

echo "Added $proxy_added proxy narinfos ($proxy_deferred deferred)"
echo "Uploaded $uploaded_paths custom paths; $deferred_paths custom paths remain pending"
echo "R2 now uses $(human_bytes "$bucket_bytes") of $(human_bytes "$R2_STORAGE_LIMIT_BYTES")"
