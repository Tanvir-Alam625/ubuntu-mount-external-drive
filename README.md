# Fix: External Hard Drive / USB Not Mounting or Not Showing in Ubuntu (NTFS, exFAT, FAT32)

A simple, working **Bash script** to **automatically mount external drives** (NTFS, exFAT, FAT32, vfat) by **partition label** on **Ubuntu, Debian, Linux Mint, Pop!_OS, Kali Linux, and other Linux distributions**.

> If your external hard disk or USB pen drive is **not showing up**, **not mounting**, shows **"unable to access volume"**, **"wrong fs type"**, **"read-only filesystem"**, or **"Error mounting /dev/sdb1"** in Ubuntu — this script fixes it.

---

## Table of Contents

- [Problem](#problem)
- [Why this happens](#why-this-happens)
- [Solution](#solution)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [How it works](#how-it-works)
- [Customization](#customization)
- [Unmounting](#unmounting)
- [Troubleshooting](#troubleshooting)
- [Keywords](#keywords)
- [License](#license)

---

## Problem

Many Ubuntu / Linux users face one or more of these issues when plugging in an external hard drive or USB flash drive:

- External hard drive **not detected** in Ubuntu file manager (Nautilus / Files)
- USB drive **not mounting automatically** after plug-in
- Error: `Error mounting /dev/sdb1 at /media/user/...: wrong fs type, bad option, bad superblock`
- Error: `unable to access "volume"`
- NTFS drive mounts as **read-only**
- exFAT partition **not recognized**
- Drive shows in `lsblk` but **not in Files app**
- Permission denied when copying files to the mounted drive
- Works on Windows but **not on Ubuntu**

This solution is **not commonly listed** in search results, so this repository exists to make it discoverable for everyone struggling with the same problem.

---

## Why this happens

- Ubuntu's auto-mount (udisks2) sometimes **fails silently** on NTFS/exFAT partitions left in a "dirty" state by Windows fast-startup.
- The kernel module for **exFAT** or **NTFS3** may not be loaded.
- The partition has a **special character in its label** that GNOME refuses to mount.
- Mount options like `uid`, `gid`, and `umask` are not applied, causing **permission issues**.
- Multiple drives with similar names cause the file manager to skip mounting.

---

## Solution

This script:

1. Detects partitions by **their label** (e.g. `New Volume`, `Song`, `Tanvir`).
2. Mounts them under a clean path: `/external-drive/<LABEL>`.
3. Applies the **correct mount options** for NTFS, exFAT, FAT32, and vfat so your normal user has full **read + write access**.
4. Opens the mounted folder in your file manager automatically.

---

## Features

- Works with **NTFS, exFAT, FAT32, vfat**
- Mounts by **partition label** (no need to guess `/dev/sdb1`, `/dev/sdc2`, etc.)
- Automatic **read/write permissions** for the logged-in user
- Safe: uses `set -euo pipefail` and clear logging
- Opens the drive automatically in your file manager
- Tested on **Ubuntu 22.04 / 24.04**, **Linux Mint**, **Pop!_OS**, **Debian 12**

---

## Requirements

Install required tools (most are already on Ubuntu):

```bash
sudo apt update
sudo apt install -y ntfs-3g exfatprogs util-linux
```

---

## Installation

Clone the repository:

```bash
git clone https://github.com/Tanvir-Alam625/ubuntu-mount-external-drive
cd ubuntu-mount-external-drive
chmod +x external-drive.sh
```

---

## Usage

Run the script with `sudo`:

```bash
sudo ./external-drive.sh
```

You will see logs like:

```
[external-drive.sh] [INFO] Searching for partition with label 'New Volume'
[external-drive.sh] [INFO] Mounting /dev/sdb1 to /external-drive/New Volume
[external-drive.sh] [INFO] Contents of /external-drive/New Volume
```

Your drives are now mounted under `/external-drive/<LABEL>` with full user permissions.

---

## How it works

1. Verifies it is running as **root** (`sudo`).
2. Reads `SUDO_UID` / `SUDO_GID` so mounted files are **owned by your normal user**, not root.
3. Uses `lsblk -o NAME,FSTYPE,LABEL` to find partitions matching your labels.
4. Builds the right mount options:
   - **vfat / fat32 / exfat / ntfs** → `uid=<you>,gid=<you>,umask=022`
5. Creates `/external-drive/<LABEL>` and mounts the partition.
6. Lists the contents and opens the folder using `xdg-open`.

---

## Customization

Open `external-drive.sh` and edit the `LABELS` array to match **your own** partition labels:

```bash
LABELS=("New Volume" "Song" "Tanvir")
```

Find your labels with:

```bash
lsblk -o NAME,FSTYPE,LABEL,SIZE
```

---

## Unmounting

When you are done, safely unmount a drive:

```bash
sudo umount "/external-drive/New Volume"
```

Or unmount everything under `/external-drive`:

```bash
sudo umount /external-drive/*
```

---

## Troubleshooting

**`mount: wrong fs type`** → install the missing driver:

```bash
sudo apt install ntfs-3g exfatprogs
```

**NTFS drive is read-only** → it was not unmounted cleanly on Windows. Fix:

```bash
sudo ntfsfix /dev/sdXN
```

Then disable **Windows Fast Startup** (Windows → Power Options).

**`xdg-open` doesn't open folder** → just browse manually to `/external-drive` in Files.

**Drive not detected at all** → check cable / port, then run:

```bash
sudo dmesg | tail -30
lsblk -f
```

---

## Keywords

`ubuntu external hard drive not mounting`, `ubuntu usb not showing`, `linux ntfs mount script`, `mount exfat ubuntu`, `auto mount external drive linux`, `ubuntu 24.04 ntfs read only fix`, `wrong fs type bad option bad superblock`, `mount partition by label linux`, `external hdd ubuntu permission denied`, `linux mint mount usb`, `pop os mount ntfs`, `bash script mount drive ubuntu`.

---

## License

MIT — free to use, modify, and share.

If this helped you, please **star the repository** so others facing the same issue can find it on Google.
