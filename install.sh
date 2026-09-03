#!/usr/bin/env bash
# =============================================================================
# install.sh — Neovim environment: fresh install OR update to latest versions
#
# Usage:
#   ./install.sh              # auto-detect mode
#   ./install.sh --install    # force full fresh install
#   ./install.sh --update     # update binaries/packages only (keeps config)
#   ./install.sh --help
#
# Manages (all at latest available version):
#   • System packages     — apt
#   • Neovim              — official binary  (github.com/neovim/neovim)
#   • Neovim-Qt           — compiled from source (github.com/equalsraf/neovim-qt)
#   • Neovide             — official binary  (github.com/neovide/neovide)
#   • Hack Nerd Font      — github.com/ryanoasis/nerd-fonts
#   • Lazygit             — official binary  (github.com/jesseduffield/lazygit)
#   • ast-grep            — official binary  (github.com/ast-grep/ast-grep)
#   • Konsole profile     — set font to Hack Nerd Font Mono (if Konsole detected)
#   • Node.js             — latest Current release via nvm (github.com/nvm-sh/nvm)
#   • npm globals         — pnpm, pyright, tree-sitter-cli, neovim
#   • pnpm globals        — @mermaid-js/mermaid-cli
#   • Python              — pynvim
#   • .desktop launchers  — nvim, nvim-qt, neovide → /usr/local/share/applications/
#   • Symlinks            — /usr/local/bin/{nvim,nvim-qt,neovide}
#   • Neovim config       — _.config/ → ~/.config/nvim  (install only)
#
# Tested on Debian Trixie / KDE Plasma Wayland (x86_64).
# Run from inside the repo directory (where _.config/ lives).
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
DIM='\033[2m'

info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[ OK ]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
die()     { echo -e "${RED}[ ERR]${RESET} $*" >&2; exit 1; }
# Use for a deliberate user cancellation (e.g. declining a confirmation
# prompt) — distinct from die() so the exit summary doesn't read as a crash.
cancel()  { echo -e "${YELLOW}[ - ]${RESET} $*"; exit 130; }

# Always print a final status line, even when the script exits early due to error
_exit_summary() {
  local code=$?
  echo ""
  if (( code == 0 )); then
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}║  Done!                                                       ║${RESET}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
  elif (( code == 130 )); then
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}${BOLD}║  Cancelled by user. No further changes were made.            ║${RESET}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
  else
    echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}${BOLD}║  Script exited with error (code $code). See output above.        ║${RESET}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
  fi
  echo ""
  echo -e "  ${BOLD}Versions at exit:${RESET}"
  command -v nvim    &>/dev/null && echo -e "    nvim    : $(nvim --version 2>/dev/null | head -1)"    || true
  command -v nvim-qt &>/dev/null && echo -e "    nvim-qt : $(nvim-qt --version 2>/dev/null | head -1)" || true
  command -v neovide &>/dev/null && echo -e "    neovide : $(neovide --version 2>/dev/null | head -1)" || true
  echo ""
}
trap _exit_summary EXIT
section() {
  echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}  $*${RESET}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# =============================================================================
# safe_remove_dir PATH EXPECTED_PREFIX
#   Removes PATH (recursively) only when:
#     • it is an absolute path
#     • its depth is ≥ 2 (not a top-level dir like /opt or /tmp)
#     • it starts with EXPECTED_PREFIX
# =============================================================================
safe_remove_dir() {
  local target="$1" expected_prefix="$2"
  [[ "$target" == /* ]]                    || die "safe_remove_dir: not absolute: $target"
  local depth; depth=$(echo "$target" | tr -cd '/' | wc -c)
  (( depth >= 2 ))                         || die "safe_remove_dir: path too shallow: $target"
  [[ "$target" == "$expected_prefix"* ]]   || die "safe_remove_dir: outside allowed prefix ($expected_prefix): $target"
  if [[ -d "$target" ]]; then sudo rm -rf "$target"; info "Removed dir: $target"; fi
}

# =============================================================================
# safe_remove_file PATH EXPECTED_PREFIX
# =============================================================================
safe_remove_file() {
  local target="$1" expected_prefix="$2"
  [[ "$target" == /* ]]                    || die "safe_remove_file: not absolute: $target"
  [[ "$target" == "$expected_prefix"* ]]   || die "safe_remove_file: outside allowed prefix ($expected_prefix): $target"
  if [[ -f "$target" ]]; then sudo rm -f "$target"; info "Removed file: $target"; fi
}

# =============================================================================
# safe_remove_tmp FILE   — only /tmp files created by mktemp
# =============================================================================
safe_remove_tmp() {
  local f="$1"
  [[ "$f" == /tmp/* ]] || die "safe_remove_tmp: not a /tmp file: $f"
  if [[ -f "$f" ]]; then rm -f "$f"; fi
}

# ── Parse args ────────────────────────────────────────────────────────────────
MODE=""
case "${1:-}" in
  --install) MODE="install" ;;
  --update)  MODE="update"  ;;
  --help|-h)
    grep '^# ' "$0" | sed 's/^# //' | head -30
    exit 0
    ;;
  "") ;;
  *) die "Unknown argument: $1  (use --install, --update, or --help)" ;;
esac

# ── Resolve repo root ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/nvim"
[[ -d "$CONFIG_SRC" ]] || die "nvim/ config directory not found in $SCRIPT_DIR"

# ── Auto-detect mode ──────────────────────────────────────────────────────────
if [[ -z "$MODE" ]]; then
  command -v nvim &>/dev/null && MODE="update" || MODE="install"
fi

# =============================================================================
# Banner + interactive configuration
# =============================================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
if [[ "$MODE" == "install" ]]; then
  echo -e "${BOLD}║         Neovim environment — FRESH INSTALL                   ║${RESET}"
else
  echo -e "${BOLD}║         Neovim environment — UPDATE to latest                ║${RESET}"
fi
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Installation directory ────────────────────────────────────────────────────
echo -e "  ${BOLD}Where should binaries be installed?${RESET}"
echo -e "  ${DIM}Neovim    → <dir>/nvim-linux-x86_64/${RESET}"
echo -e "  ${DIM}Neovide   → <dir>/neovide/${RESET}"
echo -e "  ${DIM}Neovim-Qt → compiled, installed via 'make install' (to /usr/local/bin)${RESET}"
echo -e "  ${DIM}Hack Nerd Font → /usr/local/share/fonts/HackNerdFont/${RESET}"
echo ""
read -rp "  Install prefix [default: /opt]: " INSTALL_PREFIX
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt}"
INSTALL_PREFIX="${INSTALL_PREFIX%/}"   # strip trailing slash

# Validate: must be absolute, depth ≥ 1, not sensitive system dirs
[[ "$INSTALL_PREFIX" == /* ]] || die "Install prefix must be an absolute path."
case "$INSTALL_PREFIX" in
  /|/bin|/sbin|/lib*|/boot|/dev|/proc|/sys|/run|/etc|/root)
    die "Refusing to use system-critical directory as install prefix: $INSTALL_PREFIX" ;;
esac

sudo mkdir -p "$INSTALL_PREFIX"

# ── Choose which editors to install/update ────────────────────────────────────
echo ""
echo -e "  ${BOLD}Which editors to $MODE?${RESET}"
echo -e "  ${DIM}Leave blank to select all (default).${RESET}"
echo ""

_ask_yn() {
  local prompt="$1" default="${2:-y}"
  local yn_hint; [[ "$default" == "y" ]] && yn_hint="[Y/n]" || yn_hint="[y/N]"
  read -rp "  $prompt $yn_hint: " _ans
  _ans="${_ans:-$default}"
  [[ "${_ans,,}" == "y" ]]
}

DO_NVIM=true
DO_NVIMQT=true
DO_NEOVIDE=true
DO_FONT=true

if _ask_yn "Install/update Neovim (terminal)?"; then DO_NVIM=true; else DO_NVIM=false; fi
if _ask_yn "Install/update Neovim-Qt (Qt GUI)?"; then DO_NVIMQT=true; else DO_NVIMQT=false; fi
if _ask_yn "Install/update Neovide (GPU-accelerated GUI)?"; then DO_NEOVIDE=true; else DO_NEOVIDE=false; fi
if _ask_yn "Install/update Hack Nerd Font?"; then DO_FONT=true; else DO_FONT=false; fi

echo ""
echo -e "  ${BOLD}Summary:${RESET}"
echo -e "    Mode          : ${CYAN}${MODE}${RESET}"
echo -e "    Install prefix: ${CYAN}${INSTALL_PREFIX}${RESET}"
echo -e "    Neovim        : $( $DO_NVIM    && echo "${GREEN}yes${RESET}" || echo "${DIM}skip${RESET}" )"
echo -e "    Neovim-Qt     : $( $DO_NVIMQT  && echo "${GREEN}yes${RESET}" || echo "${DIM}skip${RESET}" )"
echo -e "    Neovide       : $( $DO_NEOVIDE && echo "${GREEN}yes${RESET}" || echo "${DIM}skip${RESET}" )"
echo -e "    Hack Nerd Font: $( $DO_FONT    && echo "${GREEN}yes${RESET}" || echo "${DIM}skip${RESET}" )"
echo ""
read -rp "  Continue? [Y/n]: " _GO
[[ "${_GO:-y}" =~ ^[Yy]$ ]] || cancel "Cancelled before making any changes."

# =============================================================================
# Helpers
# =============================================================================
gh_latest_tag() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4
}

gh_latest_url() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | grep '"browser_download_url"' \
    | grep -E "$2" \
    | head -1 \
    | cut -d'"' -f4
}

refresh_desktop_db() {
  sudo update-desktop-database /usr/local/share/applications 2>/dev/null || true
}

# =============================================================================
# 1. System packages (apt)
# =============================================================================
section "1 · System packages (apt)"

sudo apt-get update -qq

PKGS=(
  build-essential cmake git curl wget unzip tar
  fd-find ripgrep fswatch
  python3 python3-pip python3-autopep8
  npm nodejs
  lua5.1 liblua5.1-0-dev luarocks
  gcc g++ gdb clang-format clangd
  qt6-base-dev qt6-svg-dev libqt6svg6-dev qtchooser
  fish
)

if [[ "$MODE" == "update" ]]; then
  sudo apt-get upgrade -y "${PKGS[@]}" 2>/dev/null || sudo apt-get install -y "${PKGS[@]}"
else
  sudo apt-get install -y "${PKGS[@]}"
fi

success "apt packages up to date"

# =============================================================================
# 2. Neovim — latest official binary
# =============================================================================
if $DO_NVIM; then
  section "2 · Neovim (latest official binary)"

  NVIM_DEST="$INSTALL_PREFIX/nvim-linux-x86_64"
  NVIM_LATEST=$(gh_latest_tag "neovim/neovim")
  NVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"

  do_nvim=true
  if [[ "$MODE" == "update" ]] && command -v nvim &>/dev/null; then
    NVIM_CURRENT=$(nvim --version | head -1 | grep -oP 'v[\d.]+' | head -1)
    if [[ "$NVIM_CURRENT" == "$NVIM_LATEST" ]]; then
      success "Neovim already at latest ($NVIM_CURRENT) — skipping"
      do_nvim=false
    else
      info "Updating Neovim $NVIM_CURRENT → $NVIM_LATEST …"
    fi
  else
    info "Installing Neovim $NVIM_LATEST …"
  fi

  if $do_nvim; then
    TMP_NVIM=$(mktemp /tmp/nvim-XXXXXX.tar.gz)
    curl -fsSL "$NVIM_URL" -o "$TMP_NVIM"
    safe_remove_dir "$NVIM_DEST" "$INSTALL_PREFIX/nvim"
    sudo tar -C "$INSTALL_PREFIX" -xzf "$TMP_NVIM"
    safe_remove_tmp "$TMP_NVIM"
    sudo ln -sf "$NVIM_DEST/bin/nvim" /usr/local/bin/nvim
    success "Neovim $(nvim --version | head -1) → $NVIM_DEST"
  fi

  # nvim .desktop — fix category and expose to system launcher
  NVIM_DESKTOP="$NVIM_DEST/share/applications/nvim.desktop"
  if [[ -f "$NVIM_DESKTOP" ]]; then
    sudo sed -i 's/^Categories=.*/Categories=TextEditor;Development;/' "$NVIM_DESKTOP"
    sudo mkdir -p /usr/local/share/applications
    sudo ln -sf "$NVIM_DESKTOP" /usr/local/share/applications/nvim.desktop
    sudo update-desktop-database /usr/local/share/applications 2>/dev/null || true
    success "nvim.desktop → /usr/local/share/applications/nvim.desktop"
  fi
fi

# =============================================================================
# 3. Neovim-Qt — latest source (compiled)
# =============================================================================
if $DO_NVIMQT; then
  section "3 · Neovim-Qt (latest source)"

  NVIMQT_LATEST=$(gh_latest_tag "equalsraf/neovim-qt")
  do_nvimqt=true

  if [[ "$MODE" == "update" ]] && command -v nvim-qt &>/dev/null; then
    NVIMQT_CURRENT=$(nvim-qt --version 2>/dev/null | grep -oP 'v[\d.]+' | head -1 || echo "unknown")
    # Normalise trailing .0 so v0.2.19.0 == v0.2.19
    NVIMQT_CURRENT_N=$(echo "$NVIMQT_CURRENT" | sed 's/\.0$//')
    NVIMQT_LATEST_N=$(echo "$NVIMQT_LATEST"  | sed 's/\.0$//')
    if [[ "$NVIMQT_CURRENT_N" == "$NVIMQT_LATEST_N" ]]; then
      success "Neovim-Qt already at latest ($NVIMQT_CURRENT) — skipping"
      do_nvimqt=false
    else
      info "Updating Neovim-Qt $NVIMQT_CURRENT_N → $NVIMQT_LATEST_N …"
    fi
  else
    info "Building Neovim-Qt $NVIMQT_LATEST (this takes a few minutes) …"
  fi

  if $do_nvimqt; then
    NVIMQT_SRC="/tmp/neovim-qt-build"
    safe_remove_dir "$NVIMQT_SRC" "/tmp/neovim-qt"
    git clone --depth=1 https://github.com/equalsraf/neovim-qt.git "$NVIMQT_SRC"
    cd "$NVIMQT_SRC"
    mkdir build && cd build
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr/local \
          -DCMAKE_PREFIX_PATH=/usr/lib/qt6 \
          ..
    make -j"$(nproc)"
    sudo make install
    cd "$SCRIPT_DIR"
    safe_remove_dir "$NVIMQT_SRC" "/tmp/neovim-qt"
    success "Neovim-Qt installed → $(command -v nvim-qt)"
  fi

  # Remove stale system .desktop and install canonical one
  safe_remove_file "/usr/share/applications/nvim-qt.desktop" "/usr/share/applications/nvim"
  sudo mkdir -p /usr/local/share/applications
  sudo tee /usr/local/share/applications/nvim-qt.desktop > /dev/null << 'EOF'
[Desktop Entry]
Name=Neovim-Qt
Comment=Qt GUI for Neovim text editor
Comment[de]=Grafikschnittstelle für den Neovim Texteditor
Comment[fr]=Interface graphique pour l'éditeur de texte Neovim
Keywords=Text;Editor;Plaintext;Write;
Keywords[de]=Text;Editor;Klartext;Schreiben;
Keywords[fr]=texte;éditeur;texte brut;écrire;
MimeType=text/english;text/plain;text/x-makefile;text/x-c++hdr;text/x-c++src;text/x-chdr;text/x-csrc;text/x-java;text/x-moc;text/x-pascal;text/x-tcl;text/x-tex;application/x-shellscript;text/x-c;text/x-c++;
Exec=nvim-qt -- %F
Icon=nvim-qt
Type=Application
Terminal=false
Categories=TextEditor;Development;
EOF
  refresh_desktop_db
  success "nvim-qt.desktop → /usr/local/share/applications/"
fi

# =============================================================================
# 4. Neovide — latest official binary
# =============================================================================
if $DO_NEOVIDE; then
  section "4 · Neovide (latest official binary)"

  NEOVIDE_DEST="$INSTALL_PREFIX/neovide"
  NEOVIDE_BIN="$NEOVIDE_DEST/neovide"
  NEOVIDE_LATEST=$(gh_latest_tag "neovide/neovide")
  # Official asset is "neovide-linux-x86_64.tar" (plain tar, no gzip)
  NEOVIDE_URL=$(gh_latest_url "neovide/neovide" 'neovide-linux-x86_64\.tar"') || true
  if [[ -z "$NEOVIDE_URL" ]]; then
    NEOVIDE_URL="https://github.com/neovide/neovide/releases/latest/download/neovide-linux-x86_64.tar"
  fi

  do_neovide=true
  NEOVIDE_MARKER="$NEOVIDE_DEST/.version"

  if [[ "$MODE" == "update" ]] && [[ -f "$NEOVIDE_MARKER" ]]; then
    NEOVIDE_CURRENT=$(cat "$NEOVIDE_MARKER")
    if [[ "$NEOVIDE_CURRENT" == "$NEOVIDE_LATEST" ]]; then
      success "Neovide already at latest ($NEOVIDE_CURRENT) — skipping"
      do_neovide=false
    else
      info "Updating Neovide $NEOVIDE_CURRENT → $NEOVIDE_LATEST …"
    fi
  else
    info "Installing Neovide $NEOVIDE_LATEST …"
  fi

  if $do_neovide; then
    info "Downloading $NEOVIDE_URL …"
    TMP_NEOVIDE=$(mktemp /tmp/neovide-XXXXXX.tar)
    curl -fsSL "$NEOVIDE_URL" -o "$TMP_NEOVIDE"
    safe_remove_dir "$NEOVIDE_DEST" "$INSTALL_PREFIX/neovide"
    sudo mkdir -p "$NEOVIDE_DEST"
    sudo tar -C "$NEOVIDE_DEST" -xf "$TMP_NEOVIDE"
    safe_remove_tmp "$TMP_NEOVIDE"
    # The archive may extract a nested dir — find the binary
    if [[ ! -f "$NEOVIDE_BIN" ]]; then
      FOUND=$(find "$NEOVIDE_DEST" -maxdepth 3 -type f -name "neovide" | head -1)
      [[ -n "$FOUND" ]] || die "Could not locate 'neovide' binary after extraction"
      sudo mv "$FOUND" "$NEOVIDE_BIN"
    fi
    sudo chmod +x "$NEOVIDE_BIN"
    echo "$NEOVIDE_LATEST" | sudo tee "$NEOVIDE_MARKER" > /dev/null
    sudo ln -sf "$NEOVIDE_BIN" /usr/local/bin/neovide
    success "Neovide $NEOVIDE_LATEST → $NEOVIDE_BIN"
  fi

  # Neovide icon. This used to look only for a copy bundled inside the
  # extracted archive, but neovide-linux-x86_64.tar ships just the binary,
  # so that file never existed and the icon was silently skipped -- leaving
  # neovide.desktop declaring "Icon=neovide" with nothing to resolve it to,
  # and a blank entry in the menu and task bar. Neovide isn't packaged in
  # Debian either, so there's no icon to pick up from the system. Falls back
  # to the icon in Neovide's own repository, pinned to the tag actually
  # installed, with main as a last resort.
  NEOVIDE_ICON_SRC="$NEOVIDE_DEST/neovide.svg"
  NEOVIDE_ICON="/usr/local/share/icons/hicolor/scalable/apps/neovide.svg"
  neovide_icon_ok=false
  sudo mkdir -p "$(dirname "$NEOVIDE_ICON")"

  if [[ -f "$NEOVIDE_ICON_SRC" ]]; then
    sudo cp "$NEOVIDE_ICON_SRC" "$NEOVIDE_ICON"
    neovide_icon_ok=true
  else
    TMP_ICON=$(mktemp /tmp/neovide-icon-XXXXXX.svg)
    for ref in "${NEOVIDE_LATEST:-}" main; do
      [[ -n "$ref" ]] || continue
      # No -S here: a miss on the first ref is expected and handled by the
      # next one, so curl shouldn't print a scary 404 on the way through.
      if curl -fsL "https://raw.githubusercontent.com/neovide/neovide/$ref/assets/neovide.svg" \
              -o "$TMP_ICON"; then
        sudo cp "$TMP_ICON" "$NEOVIDE_ICON"
        neovide_icon_ok=true
        break
      fi
    done
    safe_remove_tmp "$TMP_ICON"
  fi

  if $neovide_icon_ok; then
    sudo chmod 644 "$NEOVIDE_ICON"
    # A stale hicolor cache hides the new file even though it is on disk.
    sudo gtk-update-icon-cache -f /usr/local/share/icons/hicolor 2>/dev/null || true
    success "neovide icon → $NEOVIDE_ICON"
  else
    warn "Could not obtain the Neovide icon — launcher will show no icon."
  fi

  sudo mkdir -p /usr/local/share/applications
  sudo tee /usr/local/share/applications/neovide.desktop > /dev/null << 'EOF'
[Desktop Entry]
Name=Neovide
Comment=GPU-accelerated GUI for Neovim
Keywords=Text;Editor;Neovim;
MimeType=text/english;text/plain;text/x-makefile;text/x-c++hdr;text/x-c++src;text/x-chdr;text/x-csrc;text/x-java;text/x-moc;text/x-pascal;text/x-tcl;text/x-tex;application/x-shellscript;text/x-c;text/x-c++;
Exec=neovide -- %F
Icon=neovide
Type=Application
Terminal=false
Categories=TextEditor;Development;
EOF
  refresh_desktop_db
  success "neovide.desktop → /usr/local/share/applications/"
fi

# =============================================================================
# 5. Hack Nerd Font — latest release
# =============================================================================
if $DO_FONT; then
  section "5 · Hack Nerd Font (latest)"

  FONT_DIR="/usr/local/share/fonts/HackNerdFont"
  FONT_LATEST=$(gh_latest_tag "ryanoasis/nerd-fonts")
  FONT_MARKER="$FONT_DIR/.version"
  do_font=true

  if [[ "$MODE" == "update" ]] && [[ -f "$FONT_MARKER" ]]; then
    FONT_CURRENT=$(cat "$FONT_MARKER")
    if [[ "$FONT_CURRENT" == "$FONT_LATEST" ]]; then
      success "Hack Nerd Font already at latest ($FONT_CURRENT) — skipping"
      do_font=false
    else
      info "Updating Hack Nerd Font $FONT_CURRENT → $FONT_LATEST …"
    fi
  fi

  if $do_font; then
    FONT_URL=$(gh_latest_url "ryanoasis/nerd-fonts" '"Hack\.zip"') || true
    if [[ -z "$FONT_URL" ]]; then
      FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip"
    fi
    TMP_FONT=$(mktemp /tmp/HackNF-XXXXXX.zip)
    curl -fsSL "$FONT_URL" -o "$TMP_FONT"
    sudo mkdir -p "$FONT_DIR"
    sudo unzip -o -q "$TMP_FONT" '*.ttf' -d "$FONT_DIR"
    safe_remove_tmp "$TMP_FONT"
    echo "$FONT_LATEST" | sudo tee "$FONT_MARKER" > /dev/null
    sudo fc-cache -f "$FONT_DIR" > /dev/null 2>&1
    success "Hack Nerd Font $FONT_LATEST → $FONT_DIR"
  fi
else
  section "5 · Hack Nerd Font"
  warn "Skipped by user selection."
fi

# -----------------------------------------------------------------------------
# 5b. Konsole terminal profile — point it at the Nerd Font, if applicable
# -----------------------------------------------------------------------------
# Without this, Konsole keeps using its previously configured font and the
# Nerd Font glyphs (icons in lualine/nvim-tree/lazy.nvim) render as boxes,
# even though the font itself installed fine.
if $DO_FONT && [[ -n "${KONSOLE_VERSION:-}" ]]; then
  KONSOLE_PROFILE_DIR="$HOME/.local/share/konsole"
  mapfile -t KONSOLE_PROFILES < <(find "$KONSOLE_PROFILE_DIR" -maxdepth 1 -name '*.profile' 2>/dev/null)

  if [[ ${#KONSOLE_PROFILES[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${BOLD}Konsole detected${RESET} — Nerd Font glyphs (icons) only render"
    echo -e "  correctly if the terminal profile's font is set to a Nerd Font."
    for p in "${KONSOLE_PROFILES[@]}"; do
      echo -e "    ${DIM}$(basename "$p")${RESET}"
    done
    if _ask_yn "Set these Konsole profile(s) to use 'Hack Nerd Font Mono'?" "y"; then
      for p in "${KONSOLE_PROFILES[@]}"; do
        if grep -q '^Font=' "$p"; then
          sed -i -E 's/^Font=[^,]*/Font=Hack Nerd Font Mono/' "$p"
        else
          if grep -q '^\[Appearance\]' "$p"; then
            sed -i '/^\[Appearance\]/a Font=Hack Nerd Font Mono,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1' "$p"
          else
            printf '[Appearance]\nFont=Hack Nerd Font Mono,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n\n%s\n' "$(cat "$p")" > "$p"
          fi
        fi
      done
      success "Konsole profile(s) updated — restart Konsole (or open a new tab) to apply."
    else
      info "Skipping Konsole font adjustment."
    fi
  fi
fi

# =============================================================================
# 6. Lazygit — latest release binary (used by snacks.lazygit / LazyVim)
# =============================================================================
section "6 · Lazygit (latest release binary)"

LAZYGIT_LATEST=$(gh_latest_tag "jesseduffield/lazygit") || true

if [[ -z "$LAZYGIT_LATEST" ]]; then
  warn "Could not resolve latest Lazygit release — skipping."
else
  LAZYGIT_LATEST_NUM="${LAZYGIT_LATEST#v}"
  LAZYGIT_URL="https://github.com/jesseduffield/lazygit/releases/download/${LAZYGIT_LATEST}/lazygit_${LAZYGIT_LATEST_NUM}_Linux_x86_64.tar.gz"

  do_lazygit=true
  if [[ "$MODE" == "update" ]] && command -v lazygit &>/dev/null; then
    LAZYGIT_CURRENT="v$(lazygit --version 2>/dev/null | grep -oP 'version=\K[^,]+' || echo unknown)"
    if [[ "$LAZYGIT_CURRENT" == "$LAZYGIT_LATEST" ]]; then
      success "Lazygit already at latest ($LAZYGIT_CURRENT) — skipping"
      do_lazygit=false
    else
      info "Updating Lazygit $LAZYGIT_CURRENT → $LAZYGIT_LATEST …"
    fi
  else
    info "Installing Lazygit $LAZYGIT_LATEST …"
  fi

  if $do_lazygit; then
    TMP_LAZYGIT=$(mktemp /tmp/lazygit-XXXXXX.tar.gz)
    if curl -fsSL "$LAZYGIT_URL" -o "$TMP_LAZYGIT"; then
      TMP_LAZYGIT_DIR=$(mktemp -d /tmp/lazygit-extract-XXXXXX)
      tar -C "$TMP_LAZYGIT_DIR" -xzf "$TMP_LAZYGIT" lazygit
      sudo install -m 755 "$TMP_LAZYGIT_DIR/lazygit" /usr/local/bin/lazygit
      rm -rf "$TMP_LAZYGIT_DIR"
      success "Lazygit $LAZYGIT_LATEST → /usr/local/bin/lazygit"
    else
      warn "Failed to download Lazygit — skipping."
    fi
    safe_remove_tmp "$TMP_LAZYGIT"
  fi
fi

# =============================================================================
# 7. ast-grep — latest release binary (used by grug-far.nvim for structural search)
# =============================================================================
section "7 · ast-grep (latest release binary)"

ASTGREP_LATEST=$(gh_latest_tag "ast-grep/ast-grep") || true
ASTGREP_URL=$(gh_latest_url "ast-grep/ast-grep" 'x86_64-unknown-linux-gnu.*\.zip') || true

if [[ -z "$ASTGREP_URL" ]]; then
  warn "Could not resolve ast-grep download URL — skipping (install manually if needed)."
else
  do_astgrep=true
  if [[ "$MODE" == "update" ]] && command -v ast-grep &>/dev/null; then
    ASTGREP_CURRENT="v$(ast-grep --version 2>/dev/null | grep -oP '\d[\d.]+' | head -1 || echo 0)"
    if [[ "$ASTGREP_CURRENT" == "$ASTGREP_LATEST" ]]; then
      success "ast-grep already at latest ($ASTGREP_CURRENT) — skipping"
      do_astgrep=false
    else
      info "Updating ast-grep $ASTGREP_CURRENT → $ASTGREP_LATEST …"
    fi
  else
    info "Installing ast-grep $ASTGREP_LATEST …"
  fi

  if $do_astgrep; then
    TMP_ASTGREP=$(mktemp /tmp/ast-grep-XXXXXX.zip)
    if curl -fsSL "$ASTGREP_URL" -o "$TMP_ASTGREP"; then
      TMP_ASTGREP_DIR=$(mktemp -d /tmp/ast-grep-extract-XXXXXX)
      unzip -o -q "$TMP_ASTGREP" -d "$TMP_ASTGREP_DIR"
      ASTGREP_BIN=$(find "$TMP_ASTGREP_DIR" -maxdepth 2 -type f \( -name "ast-grep" -o -name "sg" \) | head -1)
      if [[ -n "$ASTGREP_BIN" ]]; then
        sudo install -m 755 "$ASTGREP_BIN" "/usr/local/bin/$(basename "$ASTGREP_BIN")"
        success "ast-grep $ASTGREP_LATEST → /usr/local/bin/$(basename "$ASTGREP_BIN")"
      else
        warn "ast-grep binary not found in downloaded archive — skipping."
      fi
      rm -rf "$TMP_ASTGREP_DIR"
    else
      warn "Failed to download ast-grep — skipping."
    fi
    safe_remove_tmp "$TMP_ASTGREP"
  fi
fi

# -----------------------------------------------------------------------------
# 7b. Node.js — always ensure the latest Current release via nvm
# -----------------------------------------------------------------------------
# Distro-packaged Node (e.g. Debian Trixie ships Node 20) is often too old
# for modern npm tooling — pnpm, mermaid-cli and npm@latest itself require
# Node >=22 — and lags behind upstream releases regardless. nvm keeps Node/npm
# on the latest release track independent of what apt provides, and its
# prefix is user-owned so the npm installs below don't need sudo.
section "7b · Node.js (latest via nvm)"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  NVM_LATEST_TAG="$(curl -fsSL "https://api.github.com/repos/nvm-sh/nvm/releases/latest" \
    | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
  NVM_LATEST_TAG="${NVM_LATEST_TAG:-v0.40.1}"
  info "Installing nvm ${NVM_LATEST_TAG} …"
  if curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_LATEST_TAG}/install.sh" | bash; then
    success "nvm installed"
  else
    warn "nvm install failed — falling back to system Node."
  fi
fi

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck disable=SC1091
  source "$NVM_DIR/nvm.sh"
  info "Installing latest Node (Current release) via nvm …"
  if nvm install node > /dev/null 2>&1; then
    nvm use node > /dev/null 2>&1
    nvm alias default node > /dev/null 2>&1
    success "Node $(node --version) active via nvm"
  else
    warn "nvm could not install the latest Node — falling back to system Node."
  fi
else
  warn "nvm unavailable — using system Node ($(node --version 2>/dev/null || echo 'not found'))."
fi

# =============================================================================
# 8. npm global tools
# =============================================================================
section "8 · npm global tools"

NPM_BIN="$(command -v npm || true)"

if [[ -z "$NPM_BIN" ]]; then
  warn "npm not found in PATH — skipping npm global tools."
else
  NPM_PREFIX="$(npm config get prefix 2>/dev/null || echo unknown)"
  NODE_VER="$(node --version 2>/dev/null || echo unknown)"
  NPM_VER="$(npm --version 2>/dev/null || echo unknown)"

  NPM_PREFIX_WRITABLE=false
  [[ -n "$NPM_PREFIX" && "$NPM_PREFIX" != "unknown" && -w "$NPM_PREFIX" ]] && NPM_PREFIX_WRITABLE=true

  echo ""
  echo -e "  ${BOLD}Detected npm global installation:${RESET}"
  echo -e "    npm binary : ${CYAN}${NPM_BIN}${RESET}"
  echo -e "    npm prefix : ${CYAN}${NPM_PREFIX}${RESET}"
  echo -e "    node       : ${CYAN}${NODE_VER}${RESET}"
  echo -e "    npm        : ${CYAN}${NPM_VER}${RESET}"
  if $NPM_PREFIX_WRITABLE; then
    echo -e "    writable by current user: ${GREEN}yes${RESET} — sudo not required"
  else
    echo -e "    writable by current user: ${YELLOW}no${RESET} — would need sudo"
  fi
  echo ""

  USE_SUDO_NPM=true
  DEFAULT_NPM_CHOICE="y"
  $NPM_PREFIX_WRITABLE || DEFAULT_NPM_CHOICE="n"

  if _ask_yn "Use this npm prefix for global installs (no sudo)?" "$DEFAULT_NPM_CHOICE"; then
    USE_SUDO_NPM=false
    info "Installing npm globals without sudo → $NPM_PREFIX"
  else
    warn "Falling back to system npm with sudo (may hit Node engine mismatches)."
  fi

  npm_global_install() {
    local pkg="$1"; shift
    if $USE_SUDO_NPM; then
      sudo npm install -g "$@" "$pkg"
    else
      npm install -g "$@" "$pkg"
    fi
  }

  npm_global_install npm@latest || warn "npm self-update skipped (engine mismatch or permission issue)."

  for PKG in pnpm pyright tree-sitter-cli neovim; do
    info "npm install -g $PKG …"
    if [[ "$PKG" == "tree-sitter-cli" ]]; then
      # tree-sitter-cli's postinstall builds/downloads the actual `tree-sitter`
      # binary — without it, :TSUpdate fails with ENOENT for every parser.
      npm_global_install "$PKG" "--allow-scripts=$PKG" || warn "Failed to install $PKG — continuing."
    elif [[ "$PKG" == "pyright" ]]; then
      # --force avoids EEXIST when a stale binary from a previous install
      # (e.g. under a different Node prefix) already occupies the bin dir.
      npm_global_install "$PKG" "--force" || warn "Failed to install $PKG — continuing."
    else
      npm_global_install "$PKG" || warn "Failed to install $PKG — continuing."
    fi
  done
  success "npm globals processed"
fi

# pnpm was already installed above via npm — "pnpm setup" (its own
# self-bootstrap installer) is redundant here and just produces noisy
# ENOENT warnings when install-scripts are restricted.
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
mkdir -p "$PNPM_HOME/bin"
export PATH="$PNPM_HOME/bin:$PNPM_HOME:$PATH"
info "Installing mermaid-cli via pnpm …"
# pnpm >=10 blocks postinstall scripts by default and would otherwise prompt
# interactively; puppeteer's postinstall is what downloads its bundled
# Chromium, without which mmdc can't render anything.
pnpm add -g @mermaid-js/mermaid-cli --allow-build=puppeteer || warn "mermaid-cli install skipped."
success "pnpm + mermaid-cli processed"

# =============================================================================
# 7. Python packages
# =============================================================================
section "9 · Python packages"

pip3 install --user --break-system-packages --upgrade pynvim
success "pynvim up to date"

# =============================================================================
# 8. Neovim config  (install only)
# =============================================================================
if [[ "$MODE" == "install" ]]; then
  section "10 · Neovim configuration"

  CONFIG_DEST="$HOME/.config/nvim"
  STATE_DIRS=(
    "$HOME/.local/share/nvim"
    "$HOME/.local/state/nvim"
    "$HOME/.cache/nvim"
  )

  if [[ -d "$CONFIG_DEST" ]]; then
    echo ""
    warn "Existing Neovim config found at: $CONFIG_DEST"
    echo ""
    warn "Regardless of your choice below, these plugin/state directories"
    warn "will ALSO be permanently deleted in the next step (not backed up):"
    for d in "${STATE_DIRS[@]}"; do
      [[ -d "$d" ]] && echo -e "    ${YELLOW}${d}${RESET}"
    done
    echo ""
    echo -e "  ${BOLD}What do you want to do with $CONFIG_DEST?${RESET}"
    echo -e "  [1] Rename  (default) — moves to ${CONFIG_DEST}.bak.TIMESTAMP"
    echo -e "  [2] Remove            — delete permanently (asks confirmation)"
    echo -e "  [3] Cancel            — abort"
    echo ""
    read -rp "  Choice [1/2/3, default=1]: " _CHOICE
    _CHOICE="${_CHOICE:-1}"

    case "$_CHOICE" in
      1)
        BACKUP="${CONFIG_DEST}.bak.$(date +%Y%m%d-%H%M%S)"
        mv "$CONFIG_DEST" "$BACKUP"
        success "Existing config renamed → $BACKUP"
        ;;
      2)
        echo ""
        echo -e "  This will permanently delete:"
        echo -e "    ${YELLOW}${CONFIG_DEST}${RESET}"
        for d in "${STATE_DIRS[@]}"; do
          [[ -d "$d" ]] && echo -e "    ${YELLOW}${d}${RESET}"
        done
        echo ""
        read -rp "  Type 'yes' to confirm permanent deletion: " _CONFIRM
        [[ "$_CONFIRM" == "yes" ]] || cancel "Deletion not confirmed — no files were touched."
        safe_remove_dir "$CONFIG_DEST" "$HOME/.config/nvim"
        success "Existing config removed"
        ;;
      3) cancel "Cancelled — config left untouched." ;;
      *) die "Invalid choice. Aborted." ;;
    esac
  fi

  mkdir -p "$CONFIG_DEST"
  cp -r "$CONFIG_SRC/colors"    "$CONFIG_DEST/"
  cp -r "$CONFIG_SRC/lua"       "$CONFIG_DEST/"
  cp    "$CONFIG_SRC/ginit.vim"  "$CONFIG_DEST/"
  cp    "$CONFIG_SRC/init.lua"   "$CONFIG_DEST/"
  success "Config deployed → $CONFIG_DEST"

  section "11 · Clean stale Neovim state"

  safe_remove_dir "$HOME/.local/share/nvim" "$HOME/.local"
  safe_remove_dir "$HOME/.local/state/nvim" "$HOME/.local"
  safe_remove_dir "$HOME/.cache/nvim" "$HOME/.cache"
  success "Plugin state cleaned"

else
  section "10 · Config — update mode"
  warn "Config not touched (--update preserves ~/.config/nvim)."
  info "To also redeploy the config:  ./install.sh --install"
fi

# =============================================================================
# 9/10. Plugin bootstrap / update (headless)
# =============================================================================
if [[ "$MODE" == "install" ]]; then PLUGIN_SECTION="12"; else PLUGIN_SECTION="11"; fi

section "$PLUGIN_SECTION · $([ "$MODE" == install ] && echo 'Bootstrap' || echo 'Update') plugins (headless)"

info "Running :Lazy sync …"
nvim --headless "+Lazy! sync" +qa 2>/dev/null || true

if [[ "$MODE" == "update" ]]; then
  info "Running :Lazy update …"
  nvim --headless "+Lazy! update" +qa 2>/dev/null || true
fi

info "Running :TSUpdate …"
nvim --headless "+TSUpdate" +qa 2>/dev/null || true

success "Plugins $([ "$MODE" == install ] && echo 'bootstrapped' || echo 'updated')"

# =============================================================================
# 13/12. Smoke test — verify the F4/F5/F6 keymaps still work
# =============================================================================
# Plugin updates can silently break these (e.g. vim-floaterm changing what
# values --autoinsert/--autoclose accept) without any error at :Lazy sync
# time — this catches it right away instead of at the next time F5 is used.
if [[ "$MODE" == "install" ]]; then SMOKE_SECTION="13"; else SMOKE_SECTION="12"; fi

section "$SMOKE_SECTION · Smoke test (F4/F5/F6 keymaps)"

if [[ -x "$CONFIG_SRC/tests/smoke.sh" ]]; then
  if "$CONFIG_SRC/tests/smoke.sh"; then
    success "Smoke test passed"
  else
    warn "Smoke test failed — a plugin update may have broken the F4/F5/F6 keymaps."
    warn "See the [FAIL] line(s) above for what to fix in nvim/lua/config/keymaps.lua."
  fi
else
  warn "nvim/tests/smoke.sh not found — skipping smoke test."
fi

# (summary is printed by the _exit_summary trap on exit)
