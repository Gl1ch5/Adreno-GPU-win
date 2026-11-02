#!/system/bin/sh
# Restore the original DroidVM libvirglrenderer.so. Run: su -c sh restore-virgl.sh
set -e
DST=/data/data/cn.classfun.droidvm/usr/lib/libvirglrenderer.so
[ -f "$DST.orig" ] || { echo "no backup $DST.orig"; exit 1; }
am force-stop cn.classfun.droidvm 2>/dev/null || true
cp -p "$DST.orig" "$DST"
echo "OK: original restored"
