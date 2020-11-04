#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
# set -o xtrace

# Set magic variables for current file & dir
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${dir}/../../" && pwd)"

out="${root}/out/stboot-installation/mbr-bootloader"
name="stboot_mbr_installation.img"
img="${out}/${name}"
img_backup="${img}.backup"
syslinux_src="https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/"
syslinux_tar="syslinux-6.03.tar.xz"
syslinux_dir="syslinux-6.03"
syslinux_cache="${root}/cache/syslinux/"
boot_filesystem="${out}/boot_partition.vfat"
data_filesystem="${out}/../data_partition.ext4"

if [ -f "${img}" ]; then
    echo
    echo "[INFO]: backup existing image to $(realpath --relative-to="${root}" "${img_backup}")"
    mv "${img}" "${img_backup}"
fi

if [ ! -d "${out}" ]; then mkdir -p "${out}"; fi

if [ -d "${syslinux_cache}" ]; then
    echo "[INFO]: Using cached Syslinux in $(realpath --relative-to="${root}" "${syslinux_cache}")"
else
    mkdir -p "${syslinux_cache}"
    echo
    echo "[INFO]: Downloading Syslinux Bootloader"
    wget "${syslinux_src}/${syslinux_tar}" -P "${syslinux_cache}"
    tar -xf "${syslinux_cache}/${syslinux_tar}" -C "${syslinux_cache}"
fi

echo
echo "[INFO]: Constructing disk image from filesystems:"
echo "[INFO]: Using : $(realpath --relative-to="${root}" "${boot_filesystem}")"
echo "[INFO]: Using : $(realpath --relative-to="${root}" "${data_filesystem}")"

alignment=1048576
size_vfat=$((12*(1<<20)))
size_ext4=$((767*(1<<20)))
offset_vfat=$(( alignment/512 ))
offset_ext4=$(( (alignment + size_vfat + alignment)/512 ))

# insert the filesystem to a new file at offset 1MB
dd if="${boot_filesystem}" of="${img}" conv=notrunc obs=512 status=none seek=${offset_vfat}
dd if="${data_filesystem}" of="${img}" conv=notrunc obs=512 status=none seek=${offset_ext4}

# extend the file by 1MB
truncate -s "+${alignment}" "${img}"

echo "[INFO]: Adding partitions to disk image:"

# apply partitioning
parted -s --align optimal "${img}" mklabel gpt mkpart "STBOOT" fat32 "$((offset_vfat * 512))B" "$((offset_vfat * 512 + size_vfat))B" mkpart "STDATA" ext4 "$((offset_ext4 * 512))B" "$((offset_ext4 * 512 + size_ext4))B" set 1 boot on set 1 legacy_boot on

echo ""
echo "[INFO]: Installing MBR"
dd bs=440 count=1 conv=notrunc if="${syslinux_cache}/${syslinux_dir}/bios/mbr/gptmbr.bin" of="${img}" status=none

echo ""
echo "[INFO]: Image layout:"
parted -s "${img}" print

echo ""
echo "[INFO]: $(realpath --relative-to="${root}" "${img}") created."

trap - EXIT
