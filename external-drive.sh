#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[external-drive.sh]"
MOUNT_BASE="/external-drive"
LABELS=("New Volume" "Song" "Tanvir")
SUPPORTED_FSTYPES=("vfat" "fat32" "ntfs" "exfat")

log_info() {
  printf '%s %s [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$LOG_PREFIX" "$1"
}

log_warn() {
  printf '%s %s [WARN] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$LOG_PREFIX" "$1"
}

log_error() {
  printf '%s %s [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$LOG_PREFIX" "$1" >&2
}

if [[ $EUID -ne 0 ]]; then
  log_error "This script must be run as root. Use sudo."
  exit 1
fi

TARGET_UID=${SUDO_UID:-$(id -u)}
TARGET_GID=${SUDO_GID:-$(id -g)}

log_info "Starting partition mount test"
log_info "Listing block devices"
lsblk -f
log_info "Listing partition tables"
fdisk -l || parted -l

mkdir -p "$MOUNT_BASE"
chmod 755 "$MOUNT_BASE"
chown root:root "$MOUNT_BASE"

find_partition_by_label() {
  local label="$1"
  printf '%s\n' "${SUPPORTED_FSTYPES[@]}" | tr '[:upper:]' '[:lower:]' | paste -sd ',' - | {
    read -r fslist
    lsblk -o NAME,FSTYPE,LABEL -nr | awk -v lbl="$label" -v fslist="$fslist" '
      BEGIN {
        IGNORECASE = 1
        split(fslist, a, ",")
        for (i in a) valid[tolower(a[i])] = 1
      }
      {
        fs = tolower($2)
        if ($3 == lbl && fs in valid) {
          print "/dev/" $1
          exit
        }
      }
    '
  }
}

mount_options_for_type() {
  local fs_type="$1"
  case "$fs_type" in
    vfat|fat32|exfat)
      printf 'uid=%s,gid=%s,umask=022' "$TARGET_UID" "$TARGET_GID"
      ;;
    ntfs)
      printf 'uid=%s,gid=%s,umask=022' "$TARGET_UID" "$TARGET_GID"
      ;;
    *)
      printf ''
      ;;
  esac
}

for label in "${LABELS[@]}"; do
  log_info "Searching for partition with label '$label'"
  partition=$(find_partition_by_label "$label" || true)

  if [[ -z "$partition" ]]; then
    log_warn "No supported partition found with label '$label'"
    continue
  fi

  fs_type=$(lsblk -no FSTYPE "$partition" | tr '[:upper:]' '[:lower:]')
  mount_point="$MOUNT_BASE/$label"
  mount_opts=$(mount_options_for_type "$fs_type")

  mkdir -p "$mount_point"
  chmod 755 "$mount_point"
  chown root:root "$mount_point"

  if mountpoint -q "$mount_point"; then
    log_info "$mount_point is already mounted"
    continue
  fi

  if [[ -n "$mount_opts" ]]; then
    log_info "Mounting $partition to $mount_point with options '$mount_opts'"
    if mount -o "$mount_opts" "$partition" "$mount_point"; then
      log_info "Mounted $partition to $mount_point"
    else
      log_error "Failed to mount $partition to $mount_point"
      continue
    fi
  else
    log_info "Mounting $partition to $mount_point"
    if mount "$partition" "$mount_point"; then
      log_info "Mounted $partition to $mount_point"
    else
      log_error "Failed to mount $partition to $mount_point"
      continue
    fi
  fi

  log_info "Contents of $mount_point"
  ls -l "$mount_point"
done

log_info "Partition mount test completed"
log_info "Partitions mounted under $MOUNT_BASE"
log_info "Use 'sudo umount /external-drive/<label>' when you are done"

log_info "Waiting 3 seconds before opening directory..."
sleep 3

if [[ -n "$SUDO_USER" ]]; then
  log_info "Opening $MOUNT_BASE as user $SUDO_USER"
  sudo -u "$SUDO_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $SUDO_USER)/bus xdg-open "$MOUNT_BASE" &
else
  log_info "Opening $MOUNT_BASE"
  xdg-open "$MOUNT_BASE" &
fi

log_info "Directory opened"
log_info "Done"


