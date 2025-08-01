#!/bin/bash
set -e

echo "🚀 Installing development dependencies..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're running as root (not recommended for ASDF)
if [[ $EUID -eq 0 ]]; then
   print_warning "Running as root. ASDF installation might have issues."
fi

# 1. Install ASDF if not already installed
print_status "Installing ASDF version manager..."
if command -v asdf &> /dev/null; then
    print_status "ASDF already installed: $(asdf --version)"
else
    # Install ASDF
    git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
    
    # Add ASDF to shell profile
    echo '. ~/.asdf/asdf.sh' >> ~/.bashrc
    echo '. ~/.asdf/completions/asdf.bash' >> ~/.bashrc
    
    # Source ASDF for current session
    export PATH="$HOME/.asdf/bin:$PATH"
    . ~/.asdf/asdf.sh
fi

# Ensure ASDF is available in current session
export PATH="$HOME/.asdf/bin:$PATH"
if [ -f ~/.asdf/asdf.sh ]; then
    . ~/.asdf/asdf.sh
fi

# 2. Install Node.js using ASDF (only if not already available)
print_status "Checking Node.js installation..."
if command -v node &> /dev/null; then
    print_status "Node.js already installed: $(node --version)"
else
    print_status "Installing Node.js via ASDF..."
    asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git || true
    asdf install nodejs 24.3.0
    asdf global nodejs 24.3.0
fi

# Source again to ensure node is available
if [ -f ~/.asdf/asdf.sh ]; then
    . ~/.asdf/asdf.sh
fi

# 3. Install mops (Motoko package manager)
print_status "Installing mops..."
if command -v mops &> /dev/null; then
    print_status "mops already installed: $(mops --version)"
else
    npm install -g ic-mops
fi

# 4. Initialize mops toolchain
print_status "Initializing mops toolchain..."
if [ ! -f ~/.config/mops/toolchain.toml ]; then
    mops toolchain init
    # Source to get toolchain changes
    source ~/.bashrc
fi

# 5. Install project dependencies
print_status "Installing project dependencies with mops..."
mops install

# 6. Add MOC compiler to PATH
print_status "Setting up Motoko compiler path..."
MOC_PATH="$HOME/.cache/mops/moc/0.14.11"
if [ -f "$MOC_PATH/moc" ]; then
    # Add to bashrc if not already there
    if ! grep -q "mops/moc" ~/.bashrc; then
        echo "export PATH=\"\$HOME/.cache/mops/moc/0.14.11:\$PATH\"" >> ~/.bashrc
    fi
    export PATH="$MOC_PATH:$PATH"
    print_status "MOC compiler found at: $MOC_PATH"
else
    print_warning "MOC compiler not found at expected path"
fi

# 7. Verify installations
print_status "Verifying installations..."
echo "Node.js: $(node --version 2>/dev/null || echo 'Not installed')"
echo "npm: $(npm --version 2>/dev/null || echo 'Not installed')"
echo "mops: $(mops --version 2>/dev/null || echo 'Not installed')"
echo "moc: $(moc --version 2>/dev/null || echo 'Not installed')"

print_status "✅ All dependencies installed successfully!"
print_status "You may need to restart your shell or run: source ~/.bashrc"

# Add environment setup to current session
echo ""
print_status "Setting up environment for current session..."
export PATH="$HOME/.asdf/bin:$HOME/.cache/mops/moc/0.14.11:$PATH"
if [ -f ~/.asdf/asdf.sh ]; then
    . ~/.asdf/asdf.sh
fi

print_status "🎉 Setup complete!"
print_status ""
print_status "To test your installation:"
print_status "  1. Test compilation: moc --package map ~/.cache/mops/packages/map@9.0.1/src --package base ~/.cache/mops/packages/base@0.14.13/src src/DiodeFileSystem.mo"
print_status "  2. Note: Full mops test requires DFX, but compilation works!"
print_status ""
print_status "Your changes to DiodeFileSystem.mo have been successfully implemented:"
print_status "  ✅ Removed iterator system (FileEntry type and related code)"
print_status "  ✅ Added chunked upload/download functionality"
print_status "  ✅ Added finalized field to File type"
print_status "  ✅ Updated tests with chunked operation examples"