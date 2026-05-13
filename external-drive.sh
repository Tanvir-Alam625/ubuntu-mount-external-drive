#!/usr/bin/env bash
# =============================================================================
#  external-drive.sh
# -----------------------------------------------------------------------------
#  Auto-mount external drives (NTFS / exFAT / FAT32 / vfat) by partition LABEL
#  on Ubuntu / Debian / Mint / Pop!_OS / Kali, with full user read+write access.
#
#  Usage:  sudo ./external-drive.sh
# =============================================================================

# -----------------------------------------------------------------------------
# Safer Bash:
#   -e  : exit immediately if any command fails
#   -u  : error if an undefined variable is used
#   -o pipefail : a pipeline fails if ANY command in it fails (not just the last)
# -----------------------------------------------------------------------------
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Prefix shown in every log line so you can grep for this script's output.
LOG_PREFIX="[external-drive.sh]"

# All drives will be mounted under this base directory: /external-drive/<LABEL>
MOUNT_BASE="/external-drive"

# The partition LABELS we want to look for and mount.
# Change these to match YOUR drive labels.
# You can find labels with:  lsblk -o NAME,FSTYPE,LABEL,SIZE
LABELS=("New Volume" "Song" "Tanvir")

# Filesystems this script knows how to mount safely with user permissions.
SUPPORTED_FSTYPES=("vfat" "fat32" "ntfs" "exfat")

# -----------------------------------------------------------------------------
# Logging helpers — print messages with a timestamp and a level (INFO/WARN/ERROR)
# -----------------------------------------------------------------------------
log_info()  { printf '%s %s [INFO] %s\n'  "$(date '+%Y-%m-%d %H:%M:%S')" "$LOG_PREFIX" "$1"; }
log_warn()  { printf '%s %s [WARN] %s\n'  "$(date '+%Y-%m-%d %H:%M:%S')" "$LOG_PREFIX" "$1"; }
log_error() { printf '%s %s [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$LOG_PREFIX" "$1" >&2; }

# -----------------------------------------------------------------------------
# Must be root, because mounting requires root privileges.
# $EUID is the effective user ID; 0 means root.
# -----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  log_error "This script must be run as root. Use: sudo $0"
  exit 1
fi

# -----------------------------------------------------------------------------
# We are running as root via sudo, but files should belong to the NORMAL user.
# SUDO_UID / SUDO_GID are set by sudo and point to the user who ran the command.
# If those are missing (e.g. logged in as root directly), fall back to current.
# -----------------------------------------------------------------------------
TARGET_UID=${SUDO_UID:-$(id -u)}
TARGET_GID=${SUDO_GID:-$(id -g)}

# -----------------------------------------------------------------------------
# Show the user what disks/partitions Linux currently sees.
# Useful for debugging when a drive does not appear.
# -----------------------------------------------------------------------------
log_info "Starting external-drive mount script"
log_info "Listing block devices (name, filesystem, label, size, mountpoint):"
lsblk -f
log_info "Listing partition tables:"
fdisk -l || parted -l   # try fdisk first; if it fails, try parted

# -----------------------------------------------------------------------------
# Create the base mount directory (/external-drive) if it does not exist.
# Owned by the logged-in user (TARGET_UID/TARGET_GID) so the user can browse it
# without sudo. Permissions 755 = user can read/write, others can only read.
# -----------------------------------------------------------------------------
mkdir -p "$MOUNT_BASE"
chmod 755 "$MOUNT_BASE"
chown "$TARGET_UID:$TARGET_GID" "$MOUNT_BASE"

# -----------------------------------------------------------------------------
# find_partition_by_label
#   Given a partition LABEL (e.g. "Song"), print the device path (e.g. /dev/sdb1)
#   ONLY IF the filesystem is one we support.
#
#   How it works:
#     1. Build a comma-separated list of supported filesystems (lowercased).
#     2. Run lsblk to list every block device's name, filesystem type, and label.
#     3. Use awk to:
#        - compare labels case-insensitively
#        - keep only rows whose filesystem is in our supported list
#        - print the first matching device and stop
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# mount_options_for_type
#   Returns the correct `-o` options string for a given filesystem so that:
#     - files are owned by the normal user (uid/gid)
#     - permissions are 755 for dirs / 644 for files (umask=022)
#   Without these options, NTFS/exFAT/FAT often mount as ROOT-only, which is
#   why many users see "permission denied" when copying files.
# -----------------------------------------------------------------------------
mount_options_for_type() {
  local fs_type="$1"
  case "$fs_type" in
    vfat|fat32|exfat)
      printf 'uid=%s,gid=%s,umask=022' "$TARGET_UID" "$TARGET_GID"
      ;;
    ntfs)
      # ntfs-3g also accepts uid/gid/umask
      printf 'uid=%s,gid=%s,umask=022' "$TARGET_UID" "$TARGET_GID"
      ;;
    *)
      printf ''    # other filesystems: let mount choose defaults
      ;;
  esac
}

# -----------------------------------------------------------------------------
# MAIN LOOP — for each label we care about, find its partition and mount it.
# -----------------------------------------------------------------------------
for label in "${LABELS[@]}"; do
  log_info "Searching for partition with label '$label'"

  # Look up the device path. `|| true` keeps the script alive even if not found.
  partition=$(find_partition_by_label "$label" || true)

  # No matching partition? Skip and continue with the next label.
  if [[ -z "$partition" ]]; then
    log_warn "No supported partition found with label '$label' — skipping"
    continue
  fi

  # Detect the filesystem of the matched partition (lowercased).
  fs_type=$(lsblk -no FSTYPE "$partition" | tr '[:upper:]' '[:lower:]')

  # Build a per-label mount point, e.g. /external-drive/Song
  mount_point="$MOUNT_BASE/$label"

  # Get the correct mount options for this filesystem.
  mount_opts=$(mount_options_for_type "$fs_type")

  # Create the mount point directory (safe to run if it already exists).
  # Owned by the logged-in user so the folder is visible/usable without sudo.
  mkdir -p "$mount_point"
  chmod 755 "$mount_point"
  chown "$TARGET_UID:$TARGET_GID" "$mount_point"

  # Already mounted? Nothing to do, just move on.
  if mountpoint -q "$mount_point"; then
    log_info "$mount_point is already mounted — skipping"
    continue
  fi

  # Mount the partition with or without options, depending on the filesystem.
  if [[ -n "$mount_opts" ]]; then
    log_info "Mounting $partition -> $mount_point  (options: $mount_opts)"
    if mount -o "$mount_opts" "$partition" "$mount_point"; then
      log_info "Successfully mounted $partition at $mount_point"
    else
      log_error "Failed to mount $partition at $mount_point"
      continue
    fi
  else
    log_info "Mounting $partition -> $mount_point  (default options)"
    if mount "$partition" "$mount_point"; then
      log_info "Successfully mounted $partition at $mount_point"
    else
      log_error "Failed to mount $partition at $mount_point"
      continue
    fi
  fi

  # Show a quick listing so the user can confirm it worked.
  log_info "Contents of $mount_point:"
  ls -l "$mount_point"
done

log_info "All requested partitions processed"
log_info "Drives are available under: $MOUNT_BASE"
log_info "To unmount:  sudo umount '/external-drive/<LABEL>'"

# -----------------------------------------------------------------------------
# Open the mounted folder in the user's file manager (Nautilus / Files).
# We use the ORIGINAL user (SUDO_USER) so the GUI opens in their session,
# not as root. DISPLAY and DBUS_SESSION_BUS_ADDRESS are required so GUI apps
# can connect to the user's graphical session.
# -----------------------------------------------------------------------------
log_info "Waiting 3 seconds before opening the folder..."
sleep 3

if [[ -n "${SUDO_USER:-}" ]]; then
  log_info "Opening $MOUNT_BASE as user $SUDO_USER"
  sudo -u "$SUDO_USER" \
    DISPLAY=:0 \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$SUDO_USER")/bus" \
    xdg-open "$MOUNT_BASE" &
else
  log_info "Opening $MOUNT_BASE"
  xdg-open "$MOUNT_BASE" &
fi

log_info "Done."
