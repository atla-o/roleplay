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

cat > "$ROOT/README.txt" << EOF
Roleplay for Linux ($ARCH_LABEL)
Godot 4.7.2. The terrain is inside this build. Nothing is downloaded on first run.

Run
  ./run.sh
If the window stays black (Asahi Honeykrisp, or a machine without Vulkan):
  ./run-compat.sh
That forces the OpenGL 3 Compatibility renderer. Logs go to roleplay.log
next to this file.

Controls
  Robot: W throttle, S reverse, A and D steer.
  Blade: Q raises, E lowers. Z and C tilt the blade.
  Mouse or the right stick orbits the chase camera.
  Human: WASD, Shift to run, Space to jump.
  Settings is the button at the bottom left. It switches Robot and Human
  and teleports to named places (basin Slope, Ridge, Low ground, Lake;
  island Forest, Shore, Heights). Esc closes it.

Benchmark
  ./run.sh --bench
  Prints avg_fps and low1_fps after about 14 seconds, then quits.
EOF

mkdir -p "$(dirname "$TAR_PATH")"
tar -C "$STAGE" -czf "$TAR_PATH" "roleplay-linux-$ARCH_LABEL"
rm -rf "$STAGE"
echo "packed $TAR_PATH"
