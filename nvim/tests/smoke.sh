#!/usr/bin/env bash
# Runs the F4/F5/F6 keymap smoke test against the deployed Neovim config.
# Usage: nvim/tests/smoke.sh   (run after any :Lazy sync/update)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nvim --headless -c "luafile $SCRIPT_DIR/smoke.lua"
