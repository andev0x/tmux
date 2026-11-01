# =============================================================================
# tmux — Command Control Center
# Portable installer: macOS · Arch · Debian/Ubuntu · NixOS
#
#   make install          deps + fonts + link + TPM + check + reload
#   make install DEPS=0   skip the package-manager step
#   make help             list everything
# =============================================================================

SHELL := /bin/sh

REPO_DIR      := $(CURDIR)
CONFIG_DIR    := $(HOME)/.config/tmux
TMUX_CONF     := $(HOME)/.tmux.conf
TPM_DIR       := $(HOME)/.tmux/plugins/tpm
TPM_REPO      := https://github.com/tmux-plugins/tpm
TELEMETRY_DIR := $(patsubst %/,%,$(or $(TMPDIR),/tmp))/tmux-telemetry-$(shell id -u)

# Toggles (override on the command line: make install DEPS=0)
DEPS   ?= 1
FONTS  ?= 1
EXTRAS ?= 0

.DEFAULT_GOAL := help
.PHONY: help install deps fonts extras link tpm check reload clean uninstall

# -----------------------------------------------------------------------------
# help
# -----------------------------------------------------------------------------
help:
	@printf '%s\n' \
	  'tmux — Command Control Center' \
	  '' \
	  'Usage: make <target> [DEPS=0] [FONTS=0] [EXTRAS=1]' \
	  '' \
	  '  install     Full setup: dependencies, font, symlinks, TPM plugins,' \
	  '              config validation and a live reload when tmux is running' \
	  '  deps        Install tmux/git/curl/unzip via brew, pacman, apt, nix or dnf' \
	  '  fonts       Install JetBrainsMono Nerd Font' \
	  '  extras      Install optional tools (lazygit, yazi)' \
	  '  link        Point ~/.tmux.conf and ~/.config/tmux at this checkout' \
	  '  tpm         Clone TPM and install the configured plugins' \
	  '  check       Validate script syntax, telemetry output and tmux.conf' \
	  '  reload      Reload tmux.conf in the running server (if any)' \
	  '  clean       Drop the telemetry cache' \
	  '  uninstall   Remove the symlinks and the telemetry cache' \
	  '' \
	  'Examples:' \
	  '  make install                 # recommended first run' \
	  '  make install DEPS=0          # binaries already installed' \
	  '  make install FONTS=0 EXTRAS=1'

# -----------------------------------------------------------------------------
# install — ordered sub-makes: works with -j and keeps steps independent
# -----------------------------------------------------------------------------
install:
ifeq ($(DEPS),1)
	@$(MAKE) --no-print-directory deps
endif
ifeq ($(FONTS),1)
	@$(MAKE) --no-print-directory fonts
endif
ifeq ($(EXTRAS),1)
	@$(MAKE) --no-print-directory extras
endif
	@$(MAKE) --no-print-directory link
	@$(MAKE) --no-print-directory tpm
	@$(MAKE) --no-print-directory check
	@$(MAKE) --no-print-directory reload
	@printf '\n>> Installed. Open tmux, or press prefix + r in an existing session.\n'

# -----------------------------------------------------------------------------
# deps
# -----------------------------------------------------------------------------
deps:
	@set -eu; \
	os=$$(uname -s); \
	missing=""; \
	for tool in tmux git curl; do \
	  command -v $$tool >/dev/null 2>&1 || missing="$$missing $$tool"; \
	done; \
	if [ "$$os" != "Darwin" ]; then \
	  command -v unzip >/dev/null 2>&1 || missing="$$missing unzip"; \
	fi; \
	if [ -z "$$missing" ]; then \
	  echo ">> Base dependencies already installed"; \
	  exit 0; \
	fi; \
	echo ">> Missing dependencies:$$missing"; \
	if [ "$$os" = "Darwin" ]; then \
	  if ! command -v brew >/dev/null 2>&1; then \
	    echo "!! Homebrew is required to install packages on macOS."; \
	    echo "   Install it from https://brew.sh and rerun make install."; \
	    exit 1; \
	  fi; \
	  brew install $$missing; \
	else \
	  if [ -r /etc/os-release ]; then . /etc/os-release; fi; \
	  sudo=""; [ "$$(id -u)" -eq 0 ] || sudo="sudo"; \
	  case "$${ID:-$${ID_LIKE:-}}" in \
	    arch*|manjaro*|endeavouros*) \
	      $$sudo pacman -S --needed --noconfirm $$missing ;; \
	    ubuntu*|debian*|linuxmint*|pop*) \
	      $$sudo apt-get update && $$sudo apt-get install -y $$missing ;; \
	    nixos*|*nix*) \
	      if command -v nix >/dev/null 2>&1; then \
	        echo ">> NixOS detected: installing into the user profile."; \
	        echo "   For a declarative setup add tmux/git to environment.systemPackages."; \
	        nix profile install nixpkgs#tmux nixpkgs#git nixpkgs#curl nixpkgs#unzip; \
	      else \
	        echo "!! Nix not found. Add tmux, git, curl and unzip to configuration.nix."; \
	        exit 1; \
	      fi ;; \
	    fedora*|rhel*|centos*|rocky*) \
	      $$sudo dnf install -y $$missing ;; \
	    *) \
	      echo "!! Unsupported distribution '$${ID:-unknown}'."; \
	      echo "   Install manually:$$missing"; \
	      exit 1 ;; \
	  esac; \
	fi

# -----------------------------------------------------------------------------
# fonts
# -----------------------------------------------------------------------------
fonts:
	@set -eu; \
	os=$$(uname -s); \
	install_zip() { \
	  url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"; \
	  dest="$$HOME/.local/share/fonts/JetBrainsMonoNerdFont"; \
	  tmp=$$(mktemp -d); \
	  echo ">> Downloading JetBrainsMono Nerd Font"; \
	  curl -fsSL "$$url" -o "$$tmp/font.zip"; \
	  mkdir -p "$$dest"; \
	  unzip -oq "$$tmp/font.zip" -d "$$dest"; \
	  rm -rf "$$tmp"; \
	  if command -v fc-cache >/dev/null 2>&1; then fc-cache -f >/dev/null 2>&1 || true; fi; \
	  echo ">> Font installed in $$dest"; \
	}; \
	if [ "$$os" = "Darwin" ]; then \
	  if ! command -v brew >/dev/null 2>&1; then \
	    echo "!! Homebrew not found; install the font manually."; \
	    exit 1; \
	  fi; \
	  if brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then \
	    echo ">> Nerd Font already installed"; \
	  else \
	    brew install --cask font-jetbrains-mono-nerd-font; \
	  fi; \
	  exit 0; \
	fi; \
	if command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | grep -qi 'JetBrainsMono Nerd'; then \
	  echo ">> Nerd Font already installed"; \
	  exit 0; \
	fi; \
	if [ -r /etc/os-release ]; then . /etc/os-release; fi; \
	sudo=""; [ "$$(id -u)" -eq 0 ] || sudo="sudo"; \
	case "$${ID:-}" in \
	  arch*|manjaro*|endeavouros*) \
	    $$sudo pacman -S --needed --noconfirm ttf-jetbrains-mono-nerd || install_zip ;; \
	  nixos*) \
	    nix profile install nixpkgs#nerd-fonts.jetbrains-mono || install_zip ;; \
	  *) \
	    install_zip ;; \
	esac

# -----------------------------------------------------------------------------
# extras — optional tools used by the g / y popups
# -----------------------------------------------------------------------------
extras:
	@set -eu; \
	os=$$(uname -s); \
	if [ "$$os" = "Darwin" ]; then \
	  if ! command -v brew >/dev/null 2>&1; then \
	    echo "!! Homebrew not found; install lazygit and yazi manually."; \
	    exit 1; \
	  fi; \
	  brew install lazygit yazi; \
	  exit 0; \
	fi; \
	if [ -r /etc/os-release ]; then . /etc/os-release; fi; \
	sudo=""; [ "$$(id -u)" -eq 0 ] || sudo="sudo"; \
	case "$${ID:-}" in \
	  arch*|manjaro*|endeavouros*) \
	    $$sudo pacman -S --needed --noconfirm lazygit yazi ;; \
	  nixos*) \
	    nix profile install nixpkgs#lazygit nixpkgs#yazi ;; \
	  *) \
	    echo ">> lazygit/yazi are not packaged for '$${ID:-this distro}'."; \
	    echo "   Install instructions:"; \
	    echo "   https://github.com/jesseduffield/lazygit#installation"; \
	    echo "   https://github.com/sxyazi/yazi#installation" ;; \
	esac

# -----------------------------------------------------------------------------
# link — make this checkout the config directory tmux actually reads
# -----------------------------------------------------------------------------
link:
	@set -eu; \
	if [ "$(REPO_DIR)" != "$(CONFIG_DIR)" ]; then \
	  if [ -e "$(CONFIG_DIR)" ] && [ ! -L "$(CONFIG_DIR)" ]; then \
	    echo "!! $(CONFIG_DIR) exists and is not a symlink."; \
	    echo "   Move it aside, or clone this repo directly to $(CONFIG_DIR)."; \
	    exit 1; \
	  fi; \
	  mkdir -p "$$(dirname "$(CONFIG_DIR)")"; \
	  ln -sfn "$(REPO_DIR)" "$(CONFIG_DIR)"; \
	  echo ">> Linked $(CONFIG_DIR) -> $(REPO_DIR)"; \
	else \
	  echo ">> Repo already lives at $(CONFIG_DIR)"; \
	fi; \
	if [ -e "$(TMUX_CONF)" ] && [ ! -L "$(TMUX_CONF)" ]; then \
	  backup="$(TMUX_CONF).bak.$$(date +%Y%m%d%H%M%S)"; \
	  cp "$(TMUX_CONF)" "$$backup"; \
	  echo ">> Backed up existing config to $$backup"; \
	fi; \
	ln -sfn "$(CONFIG_DIR)/tmux.conf" "$(TMUX_CONF)"; \
	echo ">> Linked $(TMUX_CONF) -> $(CONFIG_DIR)/tmux.conf"

# -----------------------------------------------------------------------------
# tpm
# -----------------------------------------------------------------------------
tpm:
	@set -eu; \
	if [ ! -e "$(TMUX_CONF)" ]; then \
	  echo "!! $(TMUX_CONF) is missing; run 'make link' first."; \
	  exit 1; \
	fi; \
	if [ ! -d "$(TPM_DIR)/.git" ]; then \
	  echo ">> Cloning TPM"; \
	  mkdir -p "$$(dirname "$(TPM_DIR)")"; \
	  git clone --depth 1 "$(TPM_REPO)" "$(TPM_DIR)"; \
	fi; \
	if tmux list-sessions >/dev/null 2>&1; then \
	  tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$(HOME)/.tmux/plugins/"; \
	fi; \
	if [ -x "$(TPM_DIR)/bin/install_plugins" ]; then \
	  echo ">> Installing plugins"; \
	  "$(TPM_DIR)/bin/install_plugins"; \
	fi

# -----------------------------------------------------------------------------
# check — syntax + behaviour, no side effects on the real server
# -----------------------------------------------------------------------------
check:
	@set -eu; \
	echo ">> Script syntax"; \
	for f in scripts/*.sh; do \
	  bash -n "$$f"; \
	  printf '   ok %s\n' "$$f"; \
	done; \
	echo ">> Telemetry output"; \
	out=$$(bash scripts/cpu.sh); \
	pct=$$(printf '%s\n' "$$out" | grep -o '%' | wc -l | tr -d ' '); \
	if [ "$$pct" -ne 2 ]; then \
	  echo "!! cpu.sh returned unexpected output: $$out"; exit 1; \
	fi; \
	bash scripts/git-read.sh "$(REPO_DIR)" >/dev/null; \
	bash scripts/git-update.sh "$(REPO_DIR)" >/dev/null; \
	printf '   ok %s\n' "$$out"; \
	echo ">> tmux.conf"; \
	if ! command -v tmux >/dev/null 2>&1; then \
	  echo "!! tmux is not installed"; exit 1; \
	fi; \
	err=$$(mktemp); \
	if ! tmux -L tmux-check -f "$(REPO_DIR)/tmux.conf" new-session -d -s check 2>"$$err"; then \
	  cat "$$err"; rm -f "$$err"; exit 1; \
	fi; \
	if [ -s "$$err" ]; then \
	  cat "$$err"; \
	  tmux -L tmux-check kill-server 2>/dev/null || true; \
	  rm -f "$$err"; \
	  exit 1; \
	fi; \
	tmux -L tmux-check kill-server 2>/dev/null || true; \
	rm -f "$$err"; \
	echo "   ok tmux.conf"; \
	echo ">> tmux.conf (obsidian theme)"; \
	obs=$$(mktemp); \
	sed 's/^%hidden TMUX_THEME=.*/%hidden TMUX_THEME=obsidian/' \
	  "$(REPO_DIR)/tmux.conf" >"$$obs"; \
	err=$$(mktemp); \
	if ! tmux -L tmux-check-obsidian -f "$$obs" new-session -d -s check 2>"$$err"; then \
	  cat "$$err"; \
	  tmux -L tmux-check-obsidian kill-server 2>/dev/null || true; \
	  rm -f "$$obs" "$$err"; \
	  exit 1; \
	fi; \
	if [ -s "$$err" ]; then \
	  cat "$$err"; \
	  tmux -L tmux-check-obsidian kill-server 2>/dev/null || true; \
	  rm -f "$$obs" "$$err"; \
	  exit 1; \
	fi; \
	if ! tmux -L tmux-check-obsidian show -g status-style | grep -q 'bg=#0a0d0b'; then \
	  echo "!! obsidian theme did not apply"; \
	  tmux -L tmux-check-obsidian kill-server 2>/dev/null || true; \
	  rm -f "$$obs" "$$err"; \
	  exit 1; \
	fi; \
	tmux -L tmux-check-obsidian kill-server 2>/dev/null || true; \
	rm -f "$$obs" "$$err"; \
	echo "   ok tmux.conf (obsidian)"

# -----------------------------------------------------------------------------
# reload
# -----------------------------------------------------------------------------
reload:
	@if tmux list-sessions >/dev/null 2>&1; then \
	  tmux source-file "$(TMUX_CONF)"; \
	  echo ">> Reloaded $(TMUX_CONF)"; \
	else \
	  echo ">> No tmux server running; the config loads on next start"; \
	fi

# -----------------------------------------------------------------------------
# clean / uninstall
# -----------------------------------------------------------------------------
clean:
	@rm -rf "$(TELEMETRY_DIR)"; \
	echo ">> Cleared $(TELEMETRY_DIR)"

uninstall:
	@set -eu; \
	if [ -L "$(TMUX_CONF)" ]; then \
	  rm -f "$(TMUX_CONF)"; \
	  echo ">> Removed $(TMUX_CONF)"; \
	elif [ -e "$(TMUX_CONF)" ]; then \
	  echo "!! $(TMUX_CONF) is not a symlink; left untouched"; \
	fi; \
	if [ -L "$(CONFIG_DIR)" ]; then \
	  if [ "$$(readlink "$(CONFIG_DIR)")" = "$(REPO_DIR)" ]; then \
	    rm -f "$(CONFIG_DIR)"; \
	    echo ">> Removed $(CONFIG_DIR)"; \
	  fi; \
	fi; \
	rm -rf "$(TELEMETRY_DIR)"; \
	echo ">> Cleared telemetry cache"; \
	echo ">> Plugins left in $(TPM_DIR)"
