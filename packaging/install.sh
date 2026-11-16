#!/bin/sh
# Install Roleplay for the current user. Run this from the unpacked tarball.
set -eu
SRC=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
DEST="$HOME/.local/share/roleplay"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
ICON_ROOT="$HOME/.local/share/icons/hicolor"
LAUNCHER="$BIN_DIR/roleplay"

mkdir -p "$DEST" "$BIN_DIR" "$APP_DIR" \
  "$ICON_ROOT/256x256/apps" "$ICON_ROOT/512x512/apps"

if [ -e "$LAUNCHER" ]; then
  cp -a "$LAUNCHER" "$BIN_DIR/roleplay.bak"
fi

# Replace the previous install. Leave roleplay.bak in ~/.local/bin alone.
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SRC"/. "$DEST"/

cat > "$LAUNCHER" << EOF
#!/bin/sh
# Roleplay. Vulkan Forward+ first, then OpenGL Compatibility. See run.sh.
exec "$DEST/run.sh" "\$@"
EOF
chmod 755 "$LAUNCHER"

sed "s|^Exec=.*|Exec=$LAUNCHER|" "$SRC/roleplay.desktop" > "$APP_DIR/roleplay.desktop"
cp "$SRC/icons/hicolor/256x256/apps/roleplay.png" "$ICON_ROOT/256x256/apps/roleplay.png"
cp "$SRC/icons/hicolor/512x512/apps/roleplay.png" "$ICON_ROOT/512x512/apps/roleplay.png"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q "$ICON_ROOT" >/dev/null 2>&1 || true
fi

echo "Installed Roleplay"
echo "  $DEST"
echo "  $LAUNCHER"
echo "  $APP_DIR/roleplay.desktop"
echo "Start it with: roleplay"
echo "If the window stays black: $DEST/run-compat.sh"
