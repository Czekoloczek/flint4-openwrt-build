#!/bin/bash
# Prints the content fingerprint of a GL-BE14000 sysupgrade image.
#
#   fingerprint.sh <sysupgrade.bin> <openwrt tree> <this repository> <watched> [packages.txt]
#
# Two builds of the same sources differ in a few bytes anyway: the kernel and
# some binaries embed the build date, and every build signs its package
# database with a fresh key. The fingerprint leaves those out and keeps what an
# update would actually change on the router:
#
#   packages     name and version of every package, except base-files (its
#                version is the tree commit) and LuCI (its version is the newest
#                commit anywhere in LuCI, so it moves without any change)
#   luci         the LuCI commits that touch the packages in the image, from
#                the check job ('watched')
#   panel-luci   the commit of the LuCI panel app, which has no version
#   base-files   the content of base-files without its version stamps
#   overlay      files/ of this repository
#   kernel       kernel version, generic and mediatek patches and config,
#                kernel module packaging, and patches/ of this repository
#   dtb          the device tree inside the image
#   id           all of the above; routers update when it changes
#
# With a fifth argument the package list is also written there.
set -euo pipefail

img=$1 tree=$2 ci=$3 watched=$4 pkgout=${5:-}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xf "$img" -C "$work"
dir=$(dirname "$(find "$work" -type f -name root | head -1)")
[ -f "$dir/root" ] && [ -f "$dir/kernel" ] || { echo "no root/kernel in $img" >&2; exit 1; }
# Without root, unsquashfs cannot create /dev/console and exits non-zero after
# extracting everything else.
unsquashfs -q -n -d "$work/rootfs" "$dir/root" >/dev/null 2>&1 || true
r=$work/rootfs
[ -s "$r/lib/apk/db/installed" ] || { echo "rootfs did not unpack" >&2; exit 1; }

h() { sha256sum | cut -d' ' -f1; }

# Package list as on the router: /lib/apk/db/installed.
awk -F: '/^P:/ {p = substr($0, 3)} /^V:/ {print p " " substr($0, 3)}' \
	"$r/lib/apk/db/installed" | sort > "$work/packages"
[ -s "$work/packages" ] || { echo "empty package list" >&2; exit 1; }
[ -n "$pkgout" ] && cp "$work/packages" "$pkgout"
packages=$(awk '$1 != "base-files" && $2 !~ /^[0-9][0-9]\.[0-9][0-9][0-9]\.[0-9]+~[0-9a-f]+$/' \
	"$work/packages" | h)

luci=$(printf '%s\n' $watched | grep -E '^luci(-pl)?@' | sort | tr '\n' ' ')
panel=$(printf '%s\n' $watched | grep -E '^glinet-panel@' || true)

# base-files without the files that only carry the build's version or key.
base=$(sed 's#^/##' "$r/lib/apk/packages/base-files.list" | sort | while read -r f; do
	case "$f" in
	etc/banner|etc/openwrt_release|etc/openwrt_version|usr/lib/os-release|etc/apk/keys/*) continue ;;
	esac
	if [ -L "$r/$f" ]; then
		echo "L $(readlink "$r/$f") $f"
	elif [ -f "$r/$f" ]; then
		echo "$(h < "$r/$f") $f"
	fi
done | h)

overlay=$(git -C "$ci" rev-parse HEAD:files)

v=$(sed -n 's/^KERNEL_PATCHVER:=//p' "$tree/target/linux/mediatek/Makefile")
kernel=$( {
	git -C "$tree" ls-tree -r HEAD -- \
		"include/kernel-$v" include/kernel-version.mk \
		target/linux/generic \
		target/linux/mediatek/Makefile \
		"target/linux/mediatek/patches-$v" \
		target/linux/mediatek/files "target/linux/mediatek/files-$v" \
		"target/linux/mediatek/filogic/config-$v" \
		target/linux/mediatek/filogic/target.mk \
		package/kernel/linux
	git -C "$ci" rev-parse HEAD:patches
} | h)

# The FIT image is itself a device tree; the board's DTB is one of its blobs.
fdt=$(fdtget -l "$dir/kernel" /images | grep -m1 '^fdt')
dtb=$(fdtget -t bx "$dir/kernel" "/images/$fdt" data |
	python3 -c 'import sys; sys.stdout.buffer.write(bytes(int(b, 16) for b in sys.stdin.read().split()))' | h)

{
	echo "packages $packages"
	echo "luci ${luci% }"
	echo "panel-luci ${panel:-none}"
	echo "base-files $base"
	echo "overlay $overlay"
	echo "kernel $kernel"
	echo "dtb $dtb"
} > "$work/fp"
cat "$work/fp"
echo "id $(h < "$work/fp")"
