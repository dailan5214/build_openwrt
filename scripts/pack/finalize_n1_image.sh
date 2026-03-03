#!/usr/bin/env bash
set -euo pipefail

SOURCE_IMG=""
OUTPUT_PREFIX=""
TARGET_SIZE_GIB="6.5"
BTRFS_SIZE_MIB="5500"
STOP_QEMU="false"
QEMU_PIDFILE="/root/imwrt-qemu.pid"
QEMU_PATTERN=""
QEMU_START_SCRIPT=""

OUTPUT_IMG=""
OUTPUT_GZ=""
OUTPUT_SHA=""
MOUNT_DIR="/mnt/n1_finalize.$$"
LOOP_DEV=""
RESTART_QEMU_ON_EXIT="false"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

usage() {
  cat <<'USAGE'
Usage:
  finalize_n1_image.sh \
    --source-img /root/source.img \
    --output-prefix /root/final_name \
    [--target-size-gib 6.5] \
    [--btrfs-size-mib 5500] \
    [--stop-qemu] \
    [--qemu-pidfile /root/imwrt-qemu.pid] \
    [--qemu-pattern 'qemu-system-aarch64.*source.img'] \
    [--qemu-start-script /root/start_imwrt_btf_qemu.sh]

Output files:
  <output-prefix>.img
  <output-prefix>.img.gz
  <output-prefix>.sha256
USAGE
}

cleanup_mount_loop() {
  set +e
  if command -v mountpoint >/dev/null 2>&1; then
    if mountpoint -q "$MOUNT_DIR"; then
      umount "$MOUNT_DIR"
    fi
  else
    if mount | grep -q "on $MOUNT_DIR "; then
      umount "$MOUNT_DIR"
    fi
  fi
  if [[ -n "$LOOP_DEV" ]]; then
    losetup -d "$LOOP_DEV" >/dev/null 2>&1 || true
  fi
  rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
  set -e
}

finalize_exit() {
  cleanup_mount_loop
  if [[ "$RESTART_QEMU_ON_EXIT" == "true" ]]; then
    log "restart qemu by script: $QEMU_START_SCRIPT"
    bash "$QEMU_START_SCRIPT"
  fi
}

trap finalize_exit EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-img)
      SOURCE_IMG="${2:-}"
      shift 2
      ;;
    --output-prefix)
      OUTPUT_PREFIX="${2:-}"
      shift 2
      ;;
    --target-size-gib)
      TARGET_SIZE_GIB="${2:-}"
      shift 2
      ;;
    --btrfs-size-mib)
      BTRFS_SIZE_MIB="${2:-}"
      shift 2
      ;;
    --stop-qemu)
      STOP_QEMU="true"
      shift
      ;;
    --qemu-pidfile)
      QEMU_PIDFILE="${2:-}"
      shift 2
      ;;
    --qemu-pattern)
      QEMU_PATTERN="${2:-}"
      shift 2
      ;;
    --qemu-start-script)
      QEMU_START_SCRIPT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown arg: $1"
      ;;
  esac
done

[[ -n "$SOURCE_IMG" ]] || die "--source-img is required"
[[ -n "$OUTPUT_PREFIX" ]] || die "--output-prefix is required"
[[ -f "$SOURCE_IMG" ]] || die "source image not found: $SOURCE_IMG"

OUTPUT_IMG="${OUTPUT_PREFIX}.img"
OUTPUT_GZ="${OUTPUT_IMG}.gz"
OUTPUT_SHA="${OUTPUT_PREFIX}.sha256"

need_cmd cp
need_cmd awk
need_cmd parted
need_cmd losetup
need_cmd mount
need_cmd umount
need_cmd btrfs
need_cmd truncate
need_cmd qemu-img
need_cmd gzip
need_cmd sha256sum
need_cmd sync

if [[ "$STOP_QEMU" == "true" ]]; then
  [[ -n "$QEMU_START_SCRIPT" ]] || die "--qemu-start-script is required when --stop-qemu is enabled"
  [[ -x "$QEMU_START_SCRIPT" ]] || die "qemu start script is not executable: $QEMU_START_SCRIPT"
  log "stop qemu for consistent snapshot"
  if [[ -f "$QEMU_PIDFILE" ]]; then
    qpid="$(cat "$QEMU_PIDFILE" 2>/dev/null || true)"
    if [[ -n "$qpid" ]] && ps -p "$qpid" >/dev/null 2>&1; then
      kill "$qpid"
      sleep 2
    fi
  fi
  if [[ -n "$QEMU_PATTERN" ]]; then
    pkill -f "$QEMU_PATTERN" >/dev/null 2>&1 || true
  else
    pkill -x qemu-system-aarch64 >/dev/null 2>&1 || true
  fi
  RESTART_QEMU_ON_EXIT="true"
fi

log "copy source image to output image"
rm -f "$OUTPUT_IMG" "$OUTPUT_GZ" "$OUTPUT_GZ.tmp" "$OUTPUT_SHA"
cp --sparse=always --reflink=auto "$SOURCE_IMG" "$OUTPUT_IMG"

log "shrink btrfs filesystem in partition 2"
mkdir -p "$MOUNT_DIR"
LOOP_DEV="$(losetup --find --show --partscan "$OUTPUT_IMG")"
mount "${LOOP_DEV}p2" "$MOUNT_DIR"
btrfs filesystem resize "${BTRFS_SIZE_MIB}M" "$MOUNT_DIR"
sync
umount "$MOUNT_DIR"
losetup -d "$LOOP_DEV"
LOOP_DEV=""
rmdir "$MOUNT_DIR"

TARGET_BYTES="$(awk -v gib="$TARGET_SIZE_GIB" 'BEGIN {printf "%.0f", gib*1024*1024*1024}')"
TARGET_SECTORS=$((TARGET_BYTES / 512))
PART2_END=$((TARGET_SECTORS - 1))

PART2_START="$(parted -m "$OUTPUT_IMG" unit s print | awk -F: '$1=="2"{gsub("s","",$2); print $2}')"
[[ -n "$PART2_START" ]] || die "cannot read partition 2 start from image: $OUTPUT_IMG"
if (( PART2_END <= PART2_START )); then
  die "target size too small: part2_end=${PART2_END}, part2_start=${PART2_START}"
fi

log "resize partition 2 to end sector ${PART2_END}s"
printf 'Yes\n' | parted "$OUTPUT_IMG" ---pretend-input-tty resizepart 2 "${PART2_END}s"

log "truncate image to ${TARGET_BYTES} bytes"
truncate -s "$TARGET_BYTES" "$OUTPUT_IMG"

log "generate gzip file"
gzip -1 -c "$OUTPUT_IMG" > "$OUTPUT_GZ.tmp"
mv -f "$OUTPUT_GZ.tmp" "$OUTPUT_GZ"

log "write sha256 file"
sha256sum "$OUTPUT_IMG" "$OUTPUT_GZ" > "$OUTPUT_SHA"

log "verify outputs"
parted -s "$OUTPUT_IMG" unit s print
qemu-img info "$OUTPUT_IMG" | sed -n '1,12p'
ls -lh "$OUTPUT_IMG" "$OUTPUT_GZ" "$OUTPUT_SHA"

log "done"
