#!/usr/bin/env bash
# MCP Bass Machine - Unix/macOS One-Liner Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nationdex/mcp-bassmachine/main/install.sh | bash

set -euo pipefail

REPO_URL="https://github.com/nationdex/mcp-bassmachine.git"
INSTALL_DIR="${MCP_BASSMACHINE_HOME:-$HOME/.mcp-bassmachine}"
BIN_DIR="${MCP_BASSMACHINE_BIN:-$HOME/.local/bin}"

# ANSI Colors
BOLD="\033[1m"
CYAN="\033[38;2;0;235;255m"
MAGENTA="\033[38;2;255;45;145m"
GREEN="\033[38;2;50;255;125m"
AMBER="\033[38;2;255;185;35m"
RED="\033[38;2;255;70;70m"
RESET="\033[0m"

echo -e "${CYAN}${BOLD}🎛  Installing MCP Bass Machine...${RESET}"

# 1. Dependency checks
HAS_LUA=0
if command -v lua5.4 >/dev/null 2>&1 || command -v luajit >/dev/null 2>&1 || command -v lua5.3 >/dev/null 2>&1 || command -v lua >/dev/null 2>&1; then
  HAS_LUA=1
fi

if [ "$HAS_LUA" -eq 0 ]; then
  echo -e "${AMBER}Notice: Lua 5.X / LuaJIT not detected in PATH.${RESET}"
  echo -e "Attempting to install Lua via system package manager..."

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq lua5.4 || sudo apt-get install -y -qq luajit || true
  elif command -v brew >/dev/null 2>&1; then
    brew install lua || true
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y lua || true
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm lua || true
  elif command -v apk >/dev/null 2>&1; then
    sudo apk add --no-cache lua5.4 || true
  fi
fi

# Verify Lua again
LUA_EXEC=""
for candidate in luajit lua5.4 lua5.3 lua; do
  if command -v "$candidate" >/dev/null 2>&1; then
    LUA_EXEC="$candidate"
    break
  fi
done

if [ -z "$LUA_EXEC" ]; then
  echo -e "${RED}Error: Lua 5.X or LuaJIT is required to run MCP Bass Machine.${RESET}"
  echo "Please install lua (e.g. 'sudo apt install lua5.4' or 'brew install lua') and re-run installer."
  exit 1
fi

echo -e "Using Lua engine: ${GREEN}${LUA_EXEC}${RESET}"

# 2. Clone or Update repository
mkdir -p "$(dirname "$INSTALL_DIR")"

if [ -d "$INSTALL_DIR/.git" ]; then
  echo -e "Existing installation found at ${INSTALL_DIR}. Updating repository..."
  git -C "$INSTALL_DIR" fetch --depth=1 origin main
  git -C "$INSTALL_DIR" reset --hard origin/main
else
  echo -e "Cloning repository into ${INSTALL_DIR}..."
  rm -rf "$INSTALL_DIR"
  git clone --depth=1 "$REPO_URL" "$INSTALL_DIR"
fi

# 3. Create Symlink / Wrapper in BIN_DIR
mkdir -p "$BIN_DIR"
WRAPPER_PATH="$BIN_DIR/mcp-bassmachine"

cat << EOF > "$WRAPPER_PATH"
#!/usr/bin/env bash
exec "$INSTALL_DIR/bin/mcp-bassmachine" "\$@"
EOF

chmod +x "$WRAPPER_PATH"
chmod +x "$INSTALL_DIR/bin/mcp-bassmachine"

# 4. Verify PATH contains BIN_DIR
PATH_NEEDS_UPDATE=1
case ":$PATH:" in
  *":$BIN_DIR:"*) PATH_NEEDS_UPDATE=0 ;;
esac

if [ "$PATH_NEEDS_UPDATE" -eq 1 ]; then
  SHELL_PROFILE=""
  if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
    SHELL_PROFILE="$HOME/.zshrc"
  elif [ -n "${BASH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "bash" ]; then
    if [ -f "$HOME/.bashrc" ]; then
      SHELL_PROFILE="$HOME/.bashrc"
    else
      SHELL_PROFILE="$HOME/.bash_profile"
    fi
  fi

  if [ -n "$SHELL_PROFILE" ] && [ -f "$SHELL_PROFILE" ]; then
    if ! grep -q 'mcp-bassmachine' "$SHELL_PROFILE"; then
      echo -e "\n# MCP Bass Machine PATH" >> "$SHELL_PROFILE"
      echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$SHELL_PROFILE"
      echo -e "Added ${BIN_DIR} to ${SHELL_PROFILE}"
    fi
  fi
fi

# 5. Success Banner
echo ""
echo -e "${GREEN}${BOLD}✓ MCP Bass Machine installed successfully!${RESET}"
echo -e "Installed to:  ${CYAN}${INSTALL_DIR}${RESET}"
echo -e "Binary linked: ${CYAN}${WRAPPER_PATH}${RESET}"
echo ""
echo -e "To launch now:"
echo -e "  ${MAGENTA}${BOLD}mcp-bassmachine${RESET}"
if [ "$PATH_NEEDS_UPDATE" -eq 1 ]; then
  echo -e "${AMBER}(If 'mcp-bassmachine' is not yet found, reload your shell or run: export PATH=\"\$PATH:$BIN_DIR\")${RESET}"
fi
echo ""
