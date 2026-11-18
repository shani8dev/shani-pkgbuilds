#!/usr/bin/env python3
"""Apply a look-and-feel package's config defaults without lookandfeeltool.

Plasma 6.8.3's lookandfeeltool and plasma-apply-lookandfeel abort (the same
KConfigGroup crash family as panel layout scripting) in the harness container.
Write the keys from the package's contents/defaults file directly - the same
keys the tools write - so the harness can test the requested look at all.
"""

import os
import re
import subprocess
import sys

lnf, home, pkg = sys.argv[1:4]
defaults = os.path.join(pkg, "usr/share/plasma/look-and-feel", lnf, "contents/defaults")
file_name, groups = "", []
with open(defaults, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            parts = re.findall(r"\[([^]]+)\]", line)
            file_name, groups = parts[0], parts[1:]
        elif "=" in line and file_name:
            key, value = line.split("=", 1)
            # the LNF defaults name Kvantum's config without its directory
            cfg_file = (
                "Kvantum/kvantum.kvconfig"
                if file_name == "kvantum.kvconfig"
                else file_name
            )
            for base in (
                os.path.join(home, ".config"),
                os.path.join(home, ".config/kdedefaults"),
            ):
                cmd = ["kwriteconfig6", "--file", os.path.join(base, cfg_file)]
                for group in groups:
                    cmd += ["--group", group]
                cmd += ["--key", key.strip(), value.strip()]
                subprocess.run(cmd, check=False)
