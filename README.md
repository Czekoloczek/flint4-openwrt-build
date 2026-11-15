# OpenWrt build for GL.iNet Flint 4 (GL-BE14000)

Automated CI build of OpenWrt for the GL.iNet Flint 4, with the front TFT panel UI and signed
self-updates.
This repository holds only the workflow and the target configuration — no source tree.

**Unofficial build. No warranty.** Mainline OpenWrt supports the Flint 4 since 2026-11-03, and
official snapshot images exist; since 2026-11-14 mainline also selects the panel UI for it. This
build adds what they lack: the LuCI panel control, the packages below baked in, a few fixes
mainline does not carry yet, and automatic updates.

## What it builds

| | |
|---|---|
| Source tree | [`openwrt/openwrt`](https://github.com/openwrt/openwrt) @ `main`, plus [`patches/`](patches) |
| Target | `mediatek/filogic`, device `glinet_gl-be14000` (**not** the `-ubootmod` variant) |
| Panel UI | [`openwrt/packages`](https://github.com/openwrt/packages) — `glinet-panel-ui`, ucode + LVGL; until 2026-11-14 from [`blogic/feed-blogic`](https://github.com/blogic/feed-blogic) |
| Panel control | [`Beaverfffan/glinet-panel`](https://github.com/Beaverfffan/glinet-panel) — `luci-app-glinet-panel` |

The board support is John Crispin's, completed by JiaY-shi: the Motorcomm YT921x/YT922x DSA
stack, the YT8824 quad 2.5GbE PHY, MT7996 Wi-Fi, the RTL8261C 10G PHY, plus the PWM fan,
backlight and touchscreen drivers. Until 2026-11 it lived only in JiaY-shi's `flint4-support`
branch, which the images of this build came from; Crispin merged it into mainline on
2026-11-03. The branch no longer moves and stays available as a fallback base (`BASE: jiay`).

### Patches on top of mainline

| Patch | Why |
|---|---|
| [`kernel/999-…-honour-openwrt-netdev-name`](patches/kernel) | The 10G GMAC registers only after the RTL8261C PHY is up, often after preinit has renamed the ports, so it can stay `eth2` and the WAN never comes up. Names the netdev from the device tree before it registers. By Nilanka de Silva, from JiaY-shi's tree; mainline did not take it. |
| [`tree/0001-…-default-spi-bus-width`](patches/tree) | The panel is reported to stay dark on mainline with the stock GL.iNet U-Boot. The only difference in the panel node against JiaY-shi's tree, where it works, is the SPI bus width, which that tree misspelled and so left at default. |

Both are checked against the tree on every build: the tree patch must apply, and the kernel patch
is applied when the kernel is prepared, so a stale one fails the build rather than slipping
through. Remove a patch once mainline carries its fix.

### In the image

LuCI with `luci-ssl`, the Material theme, the dashboard module and Polish translations.
AdGuard Home, nlbwmon, `kmod-sfp` for the SFP+ cage, and the full panel stack.

Anything that needs a kernel module **must be added here** — `kmod-*` packages from the
official snapshot feed do not match this build's kernel and will refuse to install.

## Installing

> ### `*-squashfs-factory.bin` does not work. Use the sysupgrade image.
>
> Both documented paths reject the factory image, because it carries **no OpenWrt metadata**:
>
> | Path | Result |
> |---|---|
> | GL.iNet U-Boot web recovery | `UPDATE FAILED — Probably you have chosen wrong file` |
> | GL.iNet admin panel → local upgrade | `Firmware not compatible`, verification failed |
>
> ```
> IMAGE/factory.bin    := append-kernel | pad-to 32M | append-rootfs   # no metadata
> IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata             # has metadata
> ```
>
> This is not a vendor signature check. GL.iNet's stock firmware **is** OpenWrt (21.02) with a
> standard `sysupgrade`, `fwtool` and `usign`, so it accepts a sysupgrade image whose
> `supported_devices` matches the board.

From the stock GL.iNet firmware, over SSH — **on a wired connection**:

```sh
# on your computer; -O is required, Dropbear has no sftp-server
scp -O openwrt-*-squashfs-sysupgrade.bin root@192.168.8.1:/tmp/

# on the router
sha256sum /tmp/openwrt-*-squashfs-sysupgrade.bin          # compare with sha256sums
cat /tmp/sysinfo/board_name                                # must be glinet,gl-be14000
sysupgrade -T /tmp/openwrt-*-squashfs-sysupgrade.bin       # verify, writes nothing
sysupgrade -n /tmp/openwrt-*-squashfs-sysupgrade.bin       # flash, does not keep config
```

The SSH session drops mid-flash — that is expected. Wait 3–5 minutes and do not cut power.
OpenWrt comes up on `192.168.1.1` with an empty root password.

`sysupgrade -T` genuinely validates the image. A file that is not a sysupgrade image returns
exit 1 with `Image metadata not present`, so a silent exit 0 means the image is good.

### Going back to stock

The vendor bootloader is untouched, so the U-Boot web recovery always works — it just will not
take an OpenWrt image. Hold **Reset** while powering on until the screen shows a countdown, set
your computer to `192.168.1.2/24`, open `http://192.168.1.1` and upload GL.iNet's own firmware.

## Running the workflow

Two jobs. **`check`** fingerprints these and builds when **any** of them changed:

| Input | How it is read |
|---|---|
| the tree | mainline as it stood at 00:00 UTC (`MAIN_CADENCE: daily`; `every` follows its head) |
| this repository | the commit the workflow runs from, which covers `patches/` and `files/` |
| watched feed packages | the last commit touching each path in `FEED_WATCH` |
| LuCI in the image | the last commit touching `LUCI_WATCH`, code and Polish translations separately |
| LuCI panel app | the head of `PANEL_LUCI`, since `luci-app-glinet-panel` has no version |

The release tag carries them, `auto-<stamp>-<base>-<tree>-<repo>-<feeds>`, and a build runs
whenever that combination has no release yet. `check` costs seconds and runs **every 4 hours**.
Mainline moves every day, so expect about one build a day, plus one for each change to this
repository, a watched package or LuCI.

Feeds are fetched unpinned at build time, but a feed update alone would never start a build.
`FEED_WATCH` covers the packages where an update matters: AdGuard Home, acme, vnstat, nlbwmon,
the Go toolchain AdGuard Home is compiled with, and the panel UI with LVGL and its ucode binding. `LUCI_WATCH` lists the LuCI packages in the
image; `check` reads them from a 2 MB blobless clone, because translations into other languages
— most of LuCI's commits — never reach the image and must not trigger a build. Keep
`LUCI_WATCH` in step with the LuCI packages in the configuration. `feeds.buildinfo` in each
release records the exact feed commits that went in.

A release only appears when a build **finishes**, so `check` also counts in-flight runs on the
same commit and skips if one is already building — otherwise a scheduled run landing mid-build
duplicates roughly three hours of work. `force` bypasses every one of these tests, so deliberate
parallel manual builds still work.

A full build takes roughly **2.5–3.5 hours** on a standard 4 vCPU runner. Most of the tail is
the Go toolchain, which the buildroot compiles from scratch to produce AdGuard Home. ccache is
enabled and cuts later runs.

> This repository must stay **public**. Public repositories get 4 vCPU / 16 GB runners;
> private ones get 2 vCPU / 8 GB, which pushes the build close to the 6 hour job limit.

The workflow fails the build if the `-ubootmod` variant gets selected, or if the image itself —
the rootfs unpacked from the sysupgrade file — is missing a required package or the panel init
sequence, lists a runtime APK repository outside `downloads.openwrt.org` (a third-party feed
without a `packages.adb` index breaks `apk update`), loads the Wi-Fi driver with WED on, lacks
the first-boot scripts, or does not carry its own release tag and the updater with the right key.

Each release also carries `packages.txt`, `fingerprint.txt` and `sha256sums.sig`; see
[Automatic updates](#automatic-updates). The workflow signs `sha256sums` when the repository has
the `FLINT4_SIGNING_KEY` secret: an Ed25519 private key in PEM
(`openssl genpkey -algorithm ed25519`) that belongs to
[`files/usr/share/flint4-update/signing.pub`](files/usr/share/flint4-update/signing.pub). A key
that does not belong to it fails the build; without the secret the release is published unsigned,
and routers will not update to it. The private key exists only in the secret. A new key means a
new `signing.pub`, and routers take images signed with it only after one of them is flashed by
hand.

## After first boot

The package manager is `apk`, not `opkg` — OpenWrt switched with 25.12.

Attended Sysupgrade and `owut` would request an official image from OpenWrt's build server.
That one now exists for this board, but without the LuCI panel control, the packages and the
patches above. Upgrade by flashing this build's sysupgrade image from LuCI, keeping settings, or
let the router do it, see below.

### Package updates

Upgrade by flashing a newer image, not package by package. LuCI's package manager counts
updates against the official snapshot feeds, which move daily and are built against mainline:

- **base-files** and the kernel package in the official target repository belong to the
  official image, not to this one. A first-boot script
  (`files/etc/uci-defaults/99-drop-target-feed`) comments that repository out. Kernel modules
  are not offered at all: snapshots keep them in a separate `kmods/` repository the image does
  not reference, and they would not match this kernel anyway.
- **firmware** (`mt7988-wo-firmware`, `rtl8261c-firmware`, …) and **procd** come from the
  general feeds and stay visible. Leave them to the next image.
- **LuCI** always shows updates. Its version is the timestamp of the newest commit anywhere in
  the LuCI repository, so every package gets a new version even when its content is unchanged.

### Automatic updates

Images built since 2026-11-15 carry `flint4-update`, which installs newer releases of this
repository by itself. It is **off** until enabled. A router on an older image needs one of these
images flashed by hand first.

```sh
flint4-update check                                    # what it would do now; changes nothing
uci set flint4update.main.enabled=1 && uci commit flint4update
flint4-update status                                   # state and the last log lines
```

At 4:30 and again at 5:30, router time, it looks at the newest release and installs it, keeping
settings, when all of these hold:

- **The release is signed.** The router checks `sha256sums.sig` against
  `/usr/share/flint4-update/signing.pub` before it trusts any file of the release, so a release
  edited after the build is refused.
- **The image content changed.** [`scripts/fingerprint.sh`](scripts/fingerprint.sh) writes
  `fingerprint.txt`: package versions, the LuCI and panel commits, the base-files content,
  `files/`, the kernel's sources and the device tree. Two builds of the same sources get the same
  fingerprint, although their kernels and some binaries differ by the build date, so a mainline
  commit for another board does not reboot the router.
- **The WAN is idle**: under 2 Mbit/s over 30 seconds (`idle_kbps`), so a stream or a download is
  not cut. The 5:30 run tries again.

Before flashing it fetches the image of the running build as well, from that build's own signed
release, and keeps it in `/etc/flint4-update`, which survives the upgrade. After the reboot
`/etc/init.d/flint4-update` compares the router with the state recorded just before: WAN up, the
internet reachable (name lookup and TLS included), the number of LAN bridge members and Wi-Fi
interfaces, LuCI running. If any of them falls short for 10 minutes (`health_timeout`), it
flashes the kept image back and skips that release from then on.

`flint4-update run --busy --test-rollback` performs a real update that fails its health check on
purpose, to watch the rollback work once.

It cannot help with an image that does not boot far enough to run the check. The board has a
single firmware slot, so that takes the U-Boot web recovery
([Going back to stock](#going-back-to-stock)) and then this build installed from the stock
firmware again.

### 6 GHz needs a PSC channel

`channel='auto'` lets ACS pick any channel, and clients only scan the **Preferred Scanning
Channels** — 5, 21, 37, 53, 69, 85 and so on. On a non-PSC channel the radio is up and
correctly configured but effectively invisible. Set one explicitly:

```sh
uci set wireless.radio2.channel='37'   # 6135 MHz, fits a 320 MHz block
uci set wireless.default_radio0.rnr='1'
uci set wireless.default_radio1.rnr='1'
uci commit wireless && wifi reload
```

`rnr=1` makes the 2.4 and 5 GHz beacons advertise the co-located 6 GHz AP.

### Port names

Mainline names the LAN ports after the case labels, `lan2`–`lan9`; JiaY-shi's tree, and so this
build's images up to 2026-11, called the same ports `lan1`–`lan8`. A sysupgrade that keeps
settings carries the bridge's port list over, and under the other naming one port drops out.
The first-boot script `files/etc/uci-defaults/90-be14000-port-names` adds the neighbouring name
next to every `lanN` port of a bridge. netifd skips a port that does not exist, so the list then
works under both namings, a rollback to an older image included. VLANs or interfaces on a single
port are not touched; the script logs them for a look by hand (`logread -e be14000-ports`).
It writes to the kernel log, since uci-defaults run before logd starts.

### WED is off

Mainline loads `mt7996e` without WED; JiaY-shi's tree turned it on, and the build keeps it off
for either base. With WED on, the driver takes per-client byte
counters from a firmware path that reports zero for every 5 GHz client and implausible values on
2.4 GHz (608 bytes over 2156 packets), so the dashboard and `iw station dump` showed no usage.
Packet counts were right, only bytes were wrong. Flow offloading is off in this setup anyway, so
WED saved little; mac80211 now counts all bands.

### iwinfo is unreliable on MT7996

Three radios share one `phy0`. `iwinfo` reports `Channel: 0 (unknown GHz)` for the 6 GHz radio
and lists 2.4 GHz frequencies for it. Use `iw dev phy0.2-ap0 info` instead.

## Configuration

Edit [`config/be14000.config`](config/be14000.config) and push — the next scheduled check
builds it, or run the workflow manually to build right away. It is a seed fed to
`make defconfig`, so it only needs options that differ from the defaults. Files under
[`files/`](files) are copied into the image as they are; [`patches/`](patches) is described
above, [`scripts/`](scripts) holds what the workflow calls.

## Credits

Board support by [John Crispin](https://github.com/blogic) and
[JiaY-shi](https://github.com/JiaY-shi). Panel UI by John Crispin. LuCI panel control by
[Beaverfffan](https://github.com/Beaverfffan). The netdev naming fix by
[Nilanka de Silva](https://github.com/nilankadesilva). Prior art and the runtime-feed fix from
[DiGz-Au/Flint4-build](https://github.com/DiGz-Au/Flint4-build) and
[akorshun/openwrt](https://github.com/akorshun/openwrt).
This repository only automates the build.
