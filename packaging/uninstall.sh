#!/bin/sh
# Remove the current-user Roleplay install. Restores ~/.local/bin/roleplay.bak if present.
set -eu
BIN_DIR="$HOME/.local/bin"
rm -rf "$HOME/.local/share/roleplay"
rm -f "$HOME/.local/share/applications/roleplay.desktop"
rm -f "$HOME/.local/share/icons/hicolor/256x256/apps/roleplay.png"
rm -f "$HOME/.local/share/icons/hicolor/512x512/apps/roleplay.png"
rm -f "$BIN_DIR/roleplay"
if [ -e "$BIN_DIR/roleplay.bak" ]; then
  mv "$BIN_DIR/roleplay.bak" "$BIN_DIR/roleplay"
  echo "Restored $BIN_DIR/roleplay from roleplay.bak"
fi
echo "Uninstalled Roleplay"
