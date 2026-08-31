#!/usr/bin/env bash
# Idempotent bootstrap for the Diode Zone Availability Canister dev environment.
# Installs the Motoko/IC toolchain (mops, moc, pocket-ic, dfx) and project deps,
# then persists the required PATH/env vars for interactive agent shells.
set -euo pipefail

log() { printf '\033[0;32m[install]\033[0m %s\n' "$1"; }

# Pinned tool versions (keep in sync with mops.toml / README).
MOC_VERSION="0.15.1"
POCKET_IC_VERSION="15.0.0"
DFX_VERSION="0.25.1"

NPM_PREFIX="$HOME/.npm-global"
DFX_BIN="$HOME/.local/share/dfx/bin"

# 1. Use a user-writable npm global prefix. The base image's default prefix can
#    point at a root-owned location, which breaks `npm install -g`.
export NPM_CONFIG_PREFIX="$NPM_PREFIX"
mkdir -p "$NPM_PREFIX/bin"
export PATH="$NPM_PREFIX/bin:$DFX_BIN:$PATH"

# 2. Install mops (Motoko package manager).
if ! command -v mops >/dev/null 2>&1; then
  log "Installing ic-mops..."
  npm install -g ic-mops
else
  log "mops already installed: $(mops --version | head -1)"
fi

# 3. Install the mops toolchain pinned by mops.toml (moc + pocket-ic).
log "Installing mops toolchain (moc $MOC_VERSION, pocket-ic $POCKET_IC_VERSION)..."
mops toolchain use moc "$MOC_VERSION"
mops toolchain use pocket-ic "$POCKET_IC_VERSION"

# 4. Install project Motoko dependencies.
log "Installing project mops dependencies..."
mops install

# 5. Install dfx (Internet Computer SDK), pinned.
if [ ! -x "$DFX_BIN/dfx" ] && ! command -v dfx >/dev/null 2>&1; then
  log "Installing dfx $DFX_VERSION..."
  DFXVM_INIT_YES=true DFX_VERSION="$DFX_VERSION" sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"
else
  log "dfx already installed."
fi

# 6. Resolve the mops-managed moc so dfx builds with the same compiler as
#    `mops test` (dfx ships an older moc that is incompatible with base 0.15.1).
MOC_PATH="$(mops toolchain bin moc 2>/dev/null || echo "$HOME/.cache/mops/moc/$MOC_VERSION/moc")"

# 7. Persist environment for future (interactive/tmux) agent shells. Guarded so
#    re-running install does not append duplicate blocks.
BASHRC="$HOME/.bashrc"
MARKER_BEGIN="# >>> diode-zac env >>>"
MARKER_END="# <<< diode-zac env <<<"
touch "$BASHRC"
if ! grep -qF "$MARKER_BEGIN" "$BASHRC"; then
  log "Writing environment block to $BASHRC"
  {
    echo ""
    echo "$MARKER_BEGIN"
    echo "export NPM_CONFIG_PREFIX=\"$NPM_PREFIX\""
    echo "export PATH=\"$NPM_PREFIX/bin:$DFX_BIN:\$PATH\""
    echo "export DFX_MOC_PATH=\"$MOC_PATH\""
    # dfx panics with ColorOutOfRange when TERM is unset in some shells.
    echo "[ -z \"\${TERM:-}\" ] && export TERM=xterm-256color"
    echo "$MARKER_END"
  } >> "$BASHRC"
fi

log "Verifying tools:"
echo "  node: $(node --version 2>/dev/null || echo missing)"
echo "  mops: $(mops --version 2>/dev/null | head -1 || echo missing)"
echo "  moc:  $MOC_PATH"
echo "  dfx:  $("$DFX_BIN/dfx" --version 2>/dev/null || dfx --version 2>/dev/null || echo missing)"
log "Done."
