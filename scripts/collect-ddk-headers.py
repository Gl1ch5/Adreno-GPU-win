#!/usr/bin/env python3
"""Copy WDK/SDK user-mode DDI headers (and their transitive includes) that
llvm-mingw does not ship into an include/winddk directory.

usage: collect-ddk-headers.py OUT MINGW_INCLUDE SDK_INC_DIR... -- HEADER...
"""
import os, re, shutil, sys

args = sys.argv[1:]
sep = args.index("--")
out, mingw, sdk_dirs, roots = args[0], args[1], args[2:sep], args[sep + 1:]
os.makedirs(out, exist_ok=True)

index = {}
for d in sdk_dirs:
    for f in os.listdir(d):
        index.setdefault(f.lower(), os.path.join(d, f))
mingw_have = {f.lower() for f in os.listdir(mingw)}
inc_re = re.compile(r'^\s*#\s*include\s*[<"]([^>"]+)[>"]', re.M)

todo, seen = list(roots), set()
while todo:
    h = todo.pop()
    key = h.lower().replace("\\", "/")
    if key in seen or "/" in key:
        continue
    seen.add(key)
    is_root = h in roots
    if not is_root and key in mingw_have:
        continue
    src = index.get(key)
    if not src:
        continue
    dst = os.path.join(out, os.path.basename(h))
    shutil.copy(src, dst)
    # also expose a lower-case alias for case-sensitive file systems
    if os.path.basename(h) != key:
        shutil.copy(src, os.path.join(out, key))
    with open(src, errors="replace") as fh:
        todo += inc_re.findall(fh.read())
print("copied:", " ".join(sorted(os.listdir(out))))
