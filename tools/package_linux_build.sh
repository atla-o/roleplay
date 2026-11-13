#!/bin/sh
# Pack an exported Godot Linux binary into a tarball that runs without Godot.
# Usage: package_linux_build.sh <exported-binary> <tarball-path> <arch-label>
set -eu
BIN_PATH=$1
TAR_PATH=$2
ARCH_LABEL=$3
BIN_NAME=$(basename "$BIN_PATH")
STAGE=$(mktemp -d)
ROOT="$STAGE/roleplay-linux-$ARCH_LABEL"
mkdir -p "$ROOT"
cp "$BIN_PATH" "$ROOT/$BIN_NAME"
chmod 755 "$ROOT/$BIN_NAME"
# A separate .pck is included when the export did not embed it.
PCK="$(dirname "$BIN_PATH")/${BIN_NAME}.pck"
if [ -f "$PCK" ]; then
  cp "$PCK" "$ROOT/${BIN_NAME}.pck"
fi

cat > "$ROOT/run.sh" << EOF
#!/bin/sh
# Launch Roleplay. Tries Vulkan Forward+. If that fails, OpenGL Compatibility.
set -u
cd "\$(dirname "\$0")"
BIN="./$BIN_NAME"
LOG="./roleplay.log"
launch_compat() {
  echo "Starting with OpenGL Compatibility (run-compat.sh does this directly)." | tee -a "\$LOG"
  exec "\$BIN" --rendering-driver opengl3 --rendering-method gl_compatibility --log-file "\$LOG" "\$@"
}
if [ "\${ROLEPLAY_GL:-}" = "1" ]; then
  launch_compat "\$@"
fi
echo "Starting Forward+. A black window means Vulkan failed: run ./run-compat.sh" | tee -a "\$LOG"
"\$BIN" --rendering-driver vulkan --rendering-method forward_plus --log-file "\$LOG" "\$@" >>"\$LOG" 2>&1 &
pid=\$!
i=0
while [ "\$i" -lt 12 ]; do
  if ! kill -0 "\$pid" 2>/dev/null; then
    wait "\$pid" || true
    echo "Forward+ exited. Retrying with OpenGL Compatibility." | tee -a "\$LOG"
    launch_compat "\$@"
  fi
  if grep -E -q "switching to OpenGL|Failed to initialize Vulkan|VK_KHR_surface|Vulkan initialization failed|Can't create a Vulkan" "\$LOG" 2>/dev/null; then
    kill "\$pid" 2>/dev/null || true
    wait "\$pid" 2>/dev/null || true
    echo "Vulkan is not usable here. Retrying with OpenGL Compatibility." | tee -a "\$LOG"
    launch_compat "\$@"
  fi
  i=\$((i + 1))
  sleep 0.5
done
wait "\$pid"
EOF

cat > "$ROOT/run-compat.sh" << EOF
#!/bin/sh
# Asahi and other machines where Vulkan Forward+ stays black.
set -u
cd "\$(dirname "\$0")"
LOG="./roleplay.log"
echo "OpenGL Compatibility. Log: \$LOG"
exec "./$BIN_NAME" --rendering-driver opengl3 --rendering-method gl_compatibility --log-file "\$LOG" "\$@"
EOF
chmod 755 "$ROOT/run.sh" "$ROOT/run-compat.sh"

PACK=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)/packaging
cp "$PACK/roleplay.desktop" "$ROOT/roleplay.desktop"
cp "$PACK/install.sh" "$ROOT/install.sh"
cp "$PACK/uninstall.sh" "$ROOT/uninstall.sh"
chmod 755 "$ROOT/install.sh" "$ROOT/uninstall.sh"
mkdir -p "$ROOT/icons/hicolor/256x256/apps" "$ROOT/icons/hicolor/512x512/apps"
cp "$PACK/icons/hicolor/256x256/apps/roleplay.png" "$ROOT/icons/hicolor/256x256/apps/roleplay.png"
cp "$PACK/icons/hicolor/512x512/apps/roleplay.png" "$ROOT/icons/hicolor/512x512/apps/roleplay.png"

cat > "$ROOT/README.txt" << EOF
Roleplay for Linux ($ARCH_LABEL)
Godot 4.7.2. The terrain is inside this build. Nothing is downloaded on first run.
The window class is roleplay. The title is Roleplay.

Install for this user
  ./install.sh
That copies the game to ~/.local/share/roleplay, puts a launcher at
~/.local/bin/roleplay (any file already there is saved as roleplay.bak),
and installs the desktop entry and icons. Remove it with ./uninstall.sh.

Run without installing
  ./run.sh
If the window stays black (Asahi Honeykrisp, or a machine without Vulkan):
  ./run-compat.sh
The installed launcher uses the same Vulkan-then-OpenGL fallback.
Logs go to roleplay.log next to the game.

Controls
  You start in the dozer on Northern 1 — Canada. W drives, and the blade
  is already down, so the ground moves.
  S reverse, A and D steer. Q raises the blade, E lowers it.
  Move the mouse to the top edge to show Settings. H or Tab pins it
  shown, then hidden, then back to hover. Esc releases the mouse.
  Settings switches Robot and Human, and teleports to Northern 1 — Canada,
  Northern 2 — Europe, or Northern 3 — Russia.

Benchmark
  ./run.sh --bench
  Prints avg_fps and low1_fps after about 14 seconds, then quits.
EOF

mkdir -p "$(dirname "$TAR_PATH")"
tar -C "$STAGE" -czf "$TAR_PATH" "roleplay-linux-$ARCH_LABEL"
rm -rf "$STAGE"
echo "packed $TAR_PATH"
