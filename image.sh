#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$ROOT_DIR/work"

usage() {
  cat <<EOF
Usage:
  $0 clean <stage>
  $0 build <stage>
  $0 compress

Examples:
  $0 clean 2
  $0 build 2
  $0 compress
EOF
  exit 1
}

require_stage() {
  if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+$ ]]; then
    echo "Error: stage must be a non-negative integer"
    usage
  fi
}

clean_stage() {
  local start_stage="$1"

  if [[ ! -d "$WORK_DIR" ]]; then
    echo "No work directory found, nothing to clean."
    exit 0
  fi

  echo "Cleaning work directories for stage ${start_stage} and above..."

  for dir in "$WORK_DIR"/*; do
    [[ -d "$dir" ]] || continue

    # Clean stages >= start_stage
    for stage_dir in "$dir"/stage*; do
      [[ -d "$stage_dir" ]] || continue
      stage_num="${stage_dir##*stage}"
      if [[ "$stage_num" =~ ^[0-9]+$ && "$stage_num" -ge "$start_stage" ]]; then
        echo "Removing $stage_dir"
        sudo rm -rf "$stage_dir"
      fi
    done

    # Always clean export-image
    if [[ -d "$dir/export-image" ]]; then
      echo "Removing $dir/export-image"
      sudo rm -rf "$dir/export-image"
    fi
  done
}

build_stage() {
  local start_stage="$1"

  echo "Configuring SKIP files..."
  for stage_dir in "$ROOT_DIR"/stage*; do
    [[ -d "$stage_dir" ]] || continue
    stage_num="${stage_dir##*stage}"

    if [[ "$stage_num" =~ ^[0-9]+$ ]]; then
      if (( stage_num < start_stage )); then
        touch "$stage_dir/SKIP"
        echo "Skip $stage_dir"
      else
        rm -f "$stage_dir/SKIP"
        echo "Unskip $stage_dir"
      fi
    fi
  done

  local ts
  ts="$(date +"%Y%m%d-%H%M%S")"
  local log_file="$ROOT_DIR/build-${ts}.log"

  echo "Starting build from stage ${start_stage}"
  echo "Log file: $log_file"

  nohup sudo ./build.sh | tee "$log_file"
}

compress_image() {
  echo "Compressing image..."
  ./compress-img.sh
}

# -------------------------
# Main
# -------------------------

[[ $# -ge 1 ]] || usage

command="$1"
shift

case "$command" in
  clean)
    require_stage "$@"
    clean_stage "$1"
    ;;
  build)
    require_stage "$@"
    build_stage "$1"
    ;;
  compress)
    compress_image
    ;;
  *)
    echo "Unknown command: $command"
    usage
    ;;
esac
