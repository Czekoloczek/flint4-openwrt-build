#!/bin/bash
# Tests files/usr/sbin/flint4-update on this computer: a fake GitHub with
# signed releases, fake router tools and sysfs, one clean state per scenario.
# Runs the script with bash --posix, the nearest to the router's ash at hand.
# Needs bash, openssl and python3.
set -u
SCRIPT=$(cd "$(dirname "$0")/.." && pwd)/files/usr/sbin/flint4-update
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
REPO=Czekoloczek/flint4-openwrt-build
IMG=openwrt-mediatek-filogic-glinet_gl-be14000-squashfs-sysupgrade.bin
pass=0 fail=0

# Test key pair, separate from the real one.
openssl genpkey -algorithm ed25519 -out "$T/key" 2>/dev/null
openssl pkey -in "$T/key" -pubout -out "$T/pub"
openssl genpkey -algorithm ed25519 -out "$T/otherkey" 2>/dev/null

mkdir -p "$T/bin"
cat > "$T/bin/uclient-fetch" <<'E'
#!/bin/bash
out= url=
while [ $# -gt 0 ]; do case "$1" in -O) out=$2; shift 2 ;; -q) shift ;; -T|-U) shift 2 ;; *) url=$1; shift ;; esac; done
echo "$url" >> "$R/fetches"
case "$url" in
https://api.github.com/repos/*/releases/latest) src=$GH/latest.json ;;
https://github.com/*/releases/download/*) rest=${url#*/releases/download/}; src=$GH/${rest%%/*}/${rest#*/} ;;
https://api.github.com/|https://downloads.openwrt.org/) [ "${NET:-1}" = 1 ] || exit 4; src=/dev/null ;;
*) exit 8 ;;
esac
[ -f "$src" ] || [ "$src" = /dev/null ] || exit 8
if [ "$out" = - ]; then cat "$src"; else cat "$src" > "$out"; fi
E
cat > "$T/bin/jsonfilter" <<'E'
#!/bin/bash
in=/dev/stdin expr=
while [ $# -gt 0 ]; do case "$1" in -i) in=$2; shift 2 ;; -e) expr=$2; shift 2 ;; *) shift ;; esac; done
python3 -I -c '
import json,sys
d=json.load(open(sys.argv[1]))
k=sys.argv[2].split(".")[1]
v=d.get(k)
if v is None: sys.exit(1)
print(str(v).lower() if isinstance(v,bool) else v)' "$in" "$expr"
E
cat > "$T/bin/ifstatus" <<'E'
#!/bin/bash
echo "{\"up\": $([ "${WAN:-1}" = 1 ] && echo true || echo false), \"l3_device\": \"pppoe-wan\"}"
E
cat > "$T/bin/iw" <<'E'
#!/bin/bash
for i in $(seq 1 "${WIFI:-3}"); do echo "	Interface phy0.$i-ap0"; done
E
cat > "$T/bin/pidof" <<'E'
#!/bin/bash
[ "${LUCI:-1}" = 1 ]
E
cat > "$T/bin/logger" <<'E'
#!/bin/bash
[ "$1" = -t ] && shift 2; [ "$1" = -- ] && shift
echo "$*" >> "$R/log"
E
cat > "$T/bin/logread" <<'E'
#!/bin/bash
cat "$R/log" 2>/dev/null
E
cat > "$T/bin/uci" <<'E'
#!/bin/bash
[ "$1" = -q ] && shift
case "$2" in
flint4update.main.enabled) echo "${ENABLED:-0}" ;;
flint4update.main.idle_kbps) echo "${IDLE:-2000}" ;;
flint4update.main.health_timeout) echo "${TIMEOUT:-60}" ;;
esac
E
cat > "$T/bin/sysupgrade" <<'E'
#!/bin/bash
if [ "$1" = -T ]; then [ "${SYSUP_T:-0}" = 0 ]; exit; fi
echo "sysupgrade $*" >> "$R/sysupgrade.log"
sha256sum "$1" | cut -d' ' -f1 >> "$R/sysupgrade.log"
E
cat > "$T/bin/sleep" <<'E'
#!/bin/bash
# Time passes instantly; WAN counters grow by RATE kbit/s over the period.
s=$R/sys/class/net/pppoe-wan/statistics
[ -f "$s/rx_bytes" ] && echo $(( $(cat "$s/rx_bytes") + ${RATE:-0} * 1000 / 8 * $1 )) > "$s/rx_bytes"
exit 0
E
chmod +x "$T"/bin/*

# release <tag> <packages-part> [key]: a signed release in the fake GitHub.
release() {
	local d=$GH/$1 key=${3:-$T/key}
	mkdir -p "$d"
	head -c 4096 /dev/urandom > "$d/$IMG"
	printf 'packages %s\nluci luci@a luci-pl@b\npanel-luci glinet-panel@c\nbase-files b1\noverlay o1\nkernel k1\ndtb d1\n' "$2" > "$d/fingerprint.txt"
	echo "id $(sha256sum < "$d/fingerprint.txt" | cut -d' ' -f1)" >> "$d/fingerprint.txt"
	( cd "$d" && sha256sum "$IMG" fingerprint.txt > sha256sums )
	openssl pkeyutl -sign -inkey "$key" -rawin -in "$d/sha256sums" -out "$d/sha256sums.sig"
}
latest() { echo "{\"tag_name\": \"$1\"}" > "$GH/latest.json"; }
running() { printf "FLINT4_REPO='%s'\nFLINT4_TAG='%s'\n" "$REPO" "$1" > "$R/rom/etc/flint4-release"; }

setup() {
	R=$T/run/$1; rm -rf "$R"; mkdir -p "$R/rom/etc" "$R/state" "$R/sys/class/net/br-lan/brif" "$R/sys/class/net/pppoe-wan/statistics"
	GH=$R/gh; mkdir -p "$GH"
	for p in lan2 lan3 sfp phy0.0-ap0; do mkdir -p "$R/sys/class/net/br-lan/brif/$p"; done
	echo 1000 > "$R/sys/class/net/pppoe-wan/statistics/rx_bytes"; echo 1000 > "$R/sys/class/net/pppoe-wan/statistics/tx_bytes"
	export R GH FLINT4_ROM=$R/rom FLINT4_STATE=$R/state FLINT4_WORK=$R/work FLINT4_PUB=$T/pub FLINT4_SYS=$R/sys
	export PATH=$T/bin:$PATH WAN=1 NET=1 WIFI=3 LUCI=1 RATE=0 ENABLED=0 IDLE=2000 TIMEOUT=60 SYSUP_T=0
	A=auto-20261114-1336-main-e2ed57b-c9c158f-41579de
	B=auto-20261115-0833-main-7b46f95-c9c158f-41579de
	release "$A" p1; running "$A"
}
fu() { bash --posix "$SCRIPT" "$@" > "$R/out" 2>&1; }
ok() { # name, condition
	if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     log: $(tr '\n' '|' < "$R/log" 2>/dev/null)"; fi
}
logs() { grep -q -- "$1" "$R/log" 2>/dev/null; }
flashed() { [ -s "$R/sysupgrade.log" ]; }

setup 01; latest "$A"; fu run --busy
ok "up to date" 'logs "up to date: $A" && ! flashed'

setup 02; release "$B" p1; latest "$B"; fu run --busy
ok "same content: no update" 'logs "changes nothing in the image" && ! flashed'

setup 03; release "$B" p2; latest "$B"; fu run --busy
ok "new content: flashes the new image" 'logs "changes packages against" && grep -qx "$(sha256sum < $GH/$B/$IMG | cut -d" " -f1)" "$R/sysupgrade.log" && grep -q "sysupgrade $R/work/new.bin" "$R/sysupgrade.log"'
ok "  keeps the running image for rollback" 'cmp -s "$R/state/rollback.bin" "$GH/$A/$IMG" && [ "$(cat $R/state/rollback.tag)" = "$A" ]'
ok "  records pending and baseline" 'grep -qx "PENDING_TAG=$B" $R/state/pending && grep -qx "PENDING_FROM=$A" $R/state/pending && grep -qx "wifi=3" $R/state/baseline && grep -qx "lan_ports=4" $R/state/baseline'
# boot into B, healthy
running "$B"; : > "$R/sysupgrade.log"; fu health
ok "  health ok: keeps B, cleans up" 'logs "update to $B ok" && [ ! -e $R/state/pending ] && [ ! -e $R/state/rollback.bin ] && ! flashed'

setup 04; release "$B" p2 "$T/otherkey"; latest "$B"; fu run --busy
ok "wrong signature: refused" 'logs "BAD SIGNATURE" && ! flashed'

setup 05; release "$B" p2; echo tampered >> "$GH/$B/$IMG"; latest "$B"; fu run --busy
ok "tampered image: refused" 'logs "checksum mismatch for $IMG" && ! flashed'

setup 06; release "$B" p2; echo x >> "$GH/$B/fingerprint.txt"; latest "$B"; fu run --busy
ok "tampered fingerprint: refused" 'logs "checksum mismatch for fingerprint.txt" && ! flashed'

setup 07; release "$B" p2; latest "$B"; RATE=5000 fu run
ok "busy WAN: postponed" 'logs "postponed: WAN carries 5000 kbit/s" && ! flashed'

setup 08; release "$B" p2; latest "$B"; RATE=300 fu run
ok "quiet WAN: updates" 'flashed'

setup 09; release "$B" p2; latest "$B"; fu run --busy
running "$B"; : > "$R/sysupgrade.log"; WAN=0 fu health
ok "health fails (WAN down): rolls back to A" 'logs "update to $B FAILED" && logs "wan=0 (was 1)" && grep -q "sysupgrade $R/work/rollback.bin" $R/sysupgrade.log && grep -qx "$(sha256sum < $GH/$A/$IMG | cut -d" " -f1)" $R/sysupgrade.log'
ok "  marks B bad, leaves a rollback marker" 'grep -qx "$B" $R/state/bad && [ "$(cat $R/state/rolledback)" = "$A" ] && [ ! -e $R/state/pending ]'
running "$A"; : > "$R/sysupgrade.log"; fu health
ok "  next boot on A: logs it, cleans up, no flash" 'logs "running $A again after a failed update" && [ ! -e $R/state/rolledback ] && [ ! -e $R/state/rollback.bin ] && ! flashed'
: > "$R/log"; fu run --busy
ok "  B is skipped afterwards" 'logs "skipping $B" && ! flashed'

setup 10; release "$B" p2; latest "$B"; fu run --busy
running "$B"; : > "$R/sysupgrade.log"; WIFI=2 fu health
ok "health fails (one Wi-Fi interface missing)" 'logs "wifi=2 (was 3)" && flashed'

setup 11; release "$B" p2; latest "$B"; fu run --busy --test-rollback
running "$B"; : > "$R/sysupgrade.log"; fu health
ok "rollback test: rolls back at once, B not marked bad" 'logs "rollback test" && flashed && [ ! -s $R/state/bad ]'

setup 12; release "$B" p2; latest "$B"; fu run --busy
: > "$R/sysupgrade.log"; fu health
ok "update did not take: nothing happens" 'logs "did not take" && [ ! -e $R/state/pending ] && ! flashed'

setup 13; O=auto-20261101-0000-main-aaaaaaa-c9c158f-41579de; release "$O" p9; latest "$O"; fu run --busy
ok "older release: ignored" 'logs "is not newer than" && ! flashed'

setup 14; release "$B" p2; latest "$B"; fu cron
ok "cron while disabled: does nothing" '[ ! -s $R/fetches ] && ! flashed'
ENABLED=1 fu cron
ok "cron while enabled: postpone/update logic runs" 'flashed'

setup 15; release "$B" p2; latest "$B"; NET=1 SYSUP_T=1 fu run --busy
ok "sysupgrade -T rejects: refused" 'logs "sysupgrade -T rejects" && ! flashed'

setup 16; rm -f "$R/rom/etc/flint4-release"; latest "$B"; fu run --busy
ok "image without release info: refuses" 'logs "no /etc/flint4-release" && ! flashed'

setup 17; release "$B" p2; latest "$B"; rm -f "$GH/$A/$IMG"; fu run --busy
ok "running image not downloadable: refuses (no rollback)" 'logs "no image of the running build" && ! flashed'

setup 18; release "$B" p2; latest "$B"; fu check
ok "check: reports, changes nothing" 'grep -q "a run would now flash $B" $R/out && ! flashed && [ ! -e $R/state/pending ]'

echo "---- $pass passed, $fail failed"
[ "$fail" = 0 ]
