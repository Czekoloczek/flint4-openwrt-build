# OpenWrt build for GL.iNet Flint 4 (GL-BE14000)

Automated CI build of OpenWrt for the GL.iNet Flint 4, including the front TFT panel UI.
This repository holds only the workflow and the target configuration — no source tree.

**Unofficial build. No warranty.** The Flint 4 is not supported by upstream OpenWrt.

## What it builds

| | |
|---|---|
| Source tree | [`JiaY-shi/openwrt`](https://github.com/JiaY-shi/openwrt) @ `flint4-support` |
| Target | `mediatek/filogic`, device `glinet_gl-be14000` |
| Panel UI | [`blogic/feed-blogic`](https://github.com/blogic/feed-blogic) (`glinet-panel-ui`, ucode + LVGL) |
| Panel control | [`Beaverfffan/glinet-panel`](https://github.com/Beaverfffan/glinet-panel) (`luci-app-glinet-panel`) |

The `flint4-support` branch carries John Crispin's board support completed by JiaY-shi:
the Motorcomm YT921x/YT922x DSA stack, the quad 2.5GbE PHY driver, MT7996 Wi-Fi with WED,
the RTL8261C 10G PHY, the PWM fan and the TFT panel drivers.

## Running it

The workflow runs in two jobs.

**`check`** resolves the upstream branch head with `git ls-remote` and looks for a release
tagged with that commit. If one exists, the build is skipped. It costs a few seconds.

**`build`** only runs when `check` says the upstream moved. A full build takes roughly
100–170 minutes on a standard 4 vCPU runner.

The schedule fires **every 4 hours**, so a new upstream commit is picked up the same day
without rebuilding the same source over and over. Manual runs from the Actions tab default
to `force`, which builds regardless — use that after changing anything in this repository,
since the check only looks at upstream.

> This repository must stay **public**. Public repositories get 4 vCPU / 16 GB runners;
> private ones get 2 vCPU / 8 GB, which pushes the build close to the 6 hour job limit.

> GitHub disables scheduled workflows after 60 days without repository activity.
> The 4-hourly `check` job counts, so this should not go quiet on its own.

## Output

Two images land in `bin/targets/mediatek/filogic/` and are published as a release:

- `*-squashfs-factory.bin` — flash this from the GL.iNet U-Boot web recovery
- `*-squashfs-sysupgrade.bin` — for later upgrades from LuCI

## Flashing

1. Back up the stock configuration and **download the stock GL.iNet firmware first** —
   that is the way back.
2. Power the router off. Hold **Reset**, power on, keep holding until the screen shows
   a countdown.
3. Set your computer to **192.168.1.2/24**, open **http://192.168.1.1**.
4. Upload the `factory.bin`. Wait about 3 minutes. Do not cut power.

The vendor bootloader is left alone, so the same recovery path restores the stock firmware.

The build deliberately selects the plain `glinet_gl-be14000` profile, **not** the
`-ubootmod` variant — that one replaces the vendor bootloader and removes the web recovery.
The workflow fails the build if the wrong variant ends up selected.

## After first boot

OpenWrt comes up on `192.168.1.1` with an empty root password and the radios disabled.
Set a password, then configure the network. Note that the package manager is `apk`,
not `opkg` — OpenWrt switched with 25.12.

Attended Sysupgrade and `owut` will not work here: they request images from OpenWrt's
build server, which does not know this device. Upgrades stay manual.

## Configuration

Edit [`config/be14000.config`](config/be14000.config) and re-run the workflow.
It is a seed fed to `make defconfig`, so it only needs the options that differ
from the target defaults.

`kmod-sfp` is included so the 10G SFP+ cage works; the device tree declares the cage but
`CONFIG_SFP` is not built into the target. Drop it if you have no use for that port.

## Credits

Board support by [John Crispin](https://github.com/blogic) and
[JiaY-shi](https://github.com/JiaY-shi). Panel UI by John Crispin.
LuCI panel control by [Beaverfffan](https://github.com/Beaverfffan).
This repository only automates the build.
