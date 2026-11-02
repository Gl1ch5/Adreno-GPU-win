#!/usr/bin/env python3
"""Explicit case-insensitive clang VFS overlay: /winsys/sdk -> SDK dir."""
import json, os, sys
src, out = sys.argv[1], sys.argv[2]
def walk(d):
    items = []
    for n in sorted(os.listdir(d)):
        p = os.path.join(d, n)
        if os.path.isdir(p):
            items.append({"name": n, "type": "directory", "contents": walk(p)})
        else:
            items.append({"name": n, "type": "file", "external-contents": os.path.realpath(p)})
    return items
root = {"name": "/winsys/sdk", "type": "directory",
        "contents": [{"name": "Include", "type": "directory",
                      "contents": walk(os.path.join(src, "Include"))}]}
json.dump({"version": 0, "case-sensitive": "false", "use-external-names": False,
           "roots": [root]}, open(out, "w"))
