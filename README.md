# OpenWrt build for GL.iNet Flint 4 (GL-BE14000)

Automated CI build of OpenWrt for the GL.iNet Flint 4, including the front TFT panel UI.
This repository holds only the workflow and the target configuration — no source tree.

**Unofficial build. No warranty.** The Flint 4 is not supported by upstream OpenWrt.

## What it builds

| | |
|---|---|
| Source tree | [`JiaY-shi/openwrt`](https://github.com/JiaY-shi/openwrt) @ `flint4-support` |
| Target | `mediatek/filogic`, device `glinet_gl-be14000` (**not** the `-ubootmod` variant) |
| Panel UI | [`blogic/feed-blogic`](https://github.com/blogic/feed-blogic) — `glinet-panel-ui`, ucode + LVGL |
| Panel control | [`Beaverfffan/glinet-panel`](https://github.com/Beaverfffan/glinet-panel) — `luci-app-glinet-panel` |

The `flint4-support` branch carries John Crispin's board support completed by JiaY-shi:
the Motorcomm YT921x/YT922x DSA stack, the YT8824 quad 2.5GbE PHY, MT7996 Wi-Fi with WED,
the RTL8261C 10G PHY, plus the PWM fan, backlight and touchscreen drivers.

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

Two jobs. **`check`** resolves the upstream head with `git ls-remote`, takes this repository's
own commit, and looks for a release tagged `auto-<stamp>-<upstream>-<repo>`. If that exact pair
already has a release the build is skipped; **a change on either side triggers a rebuild**. It
costs seconds and runs **every 4 hours**, which also keeps the schedule from being disabled for
inactivity.

| upstream | this repo | release for the pair | decision |
|---|---|---|---|
| unchanged | unchanged | exists | skip |
| changed | unchanged | missing | build |
| unchanged | changed | missing | build |
| changed | changed | missing | build |

A release only appears when a build **finishes**, so the list above cannot see a build that
is still running. `check` therefore also counts in-flight runs on the same commit and skips
if one is already building — otherwise a scheduled run landing mid-build duplicates roughly
three hours of work. `force` bypasses every one of these tests, so deliberate parallel manual
builds still work.

**`build`** only runs when `check` says so. Manual runs default to `force`, which builds
regardless.

A full build takes roughly **2.5–3.5 hours** on a standard 4 vCPU runner. Most of the tail is
the Go toolchain, which the buildroot compiles from scratch to produce AdGuard Home. ccache is
enabled and cuts later runs.

> This repository must stay **public**. Public repositories get 4 vCPU / 16 GB runners;
> private ones get 2 vCPU / 8 GB, which pushes the build close to the 6 hour job limit.

The workflow fails the build if the configuration or the resulting image is missing anything it
should contain, if the `-ubootmod` variant gets selected, or if the blogic feed ends up as a
runtime APK repository — that last one breaks `apk update`, because blogic hosts no
`packages.adb` index.

## After first boot

The package manager is `apk`, not `opkg` — OpenWrt switched with 25.12.

Attended Sysupgrade and `owut` do **not** work here: they request images from OpenWrt's build
server, which does not know this device. Upgrades stay manual.

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

### iwinfo is unreliable on MT7996

Three radios share one `phy0`. `iwinfo` reports `Channel: 0 (unknown GHz)` for the 6 GHz radio
and lists 2.4 GHz frequencies for it. Use `iw dev phy0.2-ap0 info` instead.

## Configuration

Edit [`config/be14000.config`](config/be14000.config) and re-run the workflow with `force`.
It is a seed fed to `make defconfig`, so it only needs options that differ from the defaults.

## Credits

Board support by [John Crispin](https://github.com/blogic) and
[JiaY-shi](https://github.com/JiaY-shi). Panel UI by John Crispin. LuCI panel control by
[Beaverfffan](https://github.com/Beaverfffan). Prior art and the runtime-feed fix from
[DiGz-Au/Flint4-build](https://github.com/DiGz-Au/Flint4-build) and
[akorshun/openwrt](https://github.com/akorshun/openwrt).
This repository only automates the build.
