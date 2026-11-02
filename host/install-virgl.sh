#!/system/bin/sh
# Replace DroidVM's libvirglrenderer.so (keeps a backup). Run: su -c sh install-virgl.sh
set -e
SRC="$(cd "$(dirname "$0")" && pwd)/libvirglrenderer.so"
DST=/data/data/cn.classfun.droidvm/usr/lib/libvirglrenderer.so
[ -f "$SRC" ] || { echo "no $SRC"; exit 1; }
am force-stop cn.classfun.droidvm 2>/dev/null || true
[ -f "$DST.orig" ] || cp -p "$DST" "$DST.orig"
OWN=$(stat -c %u:%g "$DST")
cp "$SRC" "$DST.new" && chown "$OWN" "$DST.new" && chmod 644 "$DST.new"
chcon --reference="$DST" "$DST.new" 2>/dev/null || restorecon "$DST.new" 2>/dev/null || true
mv -f "$DST.new" "$DST"
echo "OK: replaced. Backup: $DST.orig"
