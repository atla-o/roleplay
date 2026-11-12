#!/usr/bin/env python3
"""Add a download strip to the exported Godot web page."""
import sys
from pathlib import Path

BAR = """
<div id="rp-downloads" style="position:fixed;top:8px;right:8px;z-index:50;font:13px/1.4 sans-serif;background:rgba(12,16,20,.72);color:#f4f1ea;padding:8px 10px;border-radius:8px;max-width:280px">
Linux builds, terrain included.
<a style="color:#9fd0ff" href="downloads/roleplay-linux-x86_64.tar.gz">x86_64</a>
· <a style="color:#9fd0ff" href="downloads/roleplay-linux-aarch64.tar.gz">arm64</a>
· <a style="color:#9fd0ff" href="downloads/">how to run</a>
</div>
"""

PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>Roleplay Linux downloads</title>
<style>
body { font: 16px/1.5 sans-serif; max-width: 42rem; margin: 2rem auto; padding: 0 1rem; color: #1c1915; }
a { color: #0b4f8a; }
code { background: #f3efe6; padding: 0 0.25rem; }
</style>
</head>
<body>
<h1>Roleplay for Linux</h1>
<p>Godot 4.7.2. The measured terrain is inside the tarball. Nothing is downloaded on first run.</p>
<ul>
<li><a href="roleplay-linux-x86_64.tar.gz">roleplay-linux-x86_64.tar.gz</a> for typical PCs</li>
<li><a href="roleplay-linux-aarch64.tar.gz">roleplay-linux-aarch64.tar.gz</a> for Asahi Linux on Apple Silicon and other arm64 machines</li>
</ul>
<p>Unpack, then <code>./run.sh</code>. If Vulkan Forward+ leaves a black window, run <code>./run-compat.sh</code>. That uses OpenGL 3 Compatibility. Output is written to <code>roleplay.log</code> beside the binary.</p>
<p>Robot: W throttle, S reverse, A and D steer. Q raises the blade, E lowers it, Z and C tilt it. Settings, bottom left, switches body and teleports. <code>./run.sh --bench</code> prints a frame rate and quits.</p>
<p><a href="../">Back to the browser preview</a></p>
</body>
</html>
"""


def main() -> None:
    index = Path(sys.argv[1])
    html = index.read_text(encoding="utf-8")
    if "rp-downloads" not in html:
        if "</body>" in html:
            html = html.replace("</body>", BAR + "\n</body>", 1)
        else:
            html += BAR
        index.write_text(html, encoding="utf-8")
    downloads = index.parent / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    (downloads / "index.html").write_text(PAGE, encoding="utf-8")


if __name__ == "__main__":
    main()
