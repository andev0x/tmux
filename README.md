# tmux — Command Control Center

A minimalist, low-cognitive-load tmux setup for high-intensity terminal work
(AI-assisted coding, Neovim, git-heavy workflows).

The design rules are simple:

- **No visual noise** — no powerline pills, badges, gradients or double clocks.
- **Micro-contrast** — one dark base, one muted slate, and accents that only
  ever mean something: **cyan** = focus, **amber** = prefix armed.
- **Telemetry that never blocks** — every status-bar script is memoised and
  sampled out of band, so the UI stays responsive even on a slow repo.

```
 󰖲 work    1:vim   2:zsh 󰍉 [Z]        󰻠 18% 󰍛 59% │ 󰊢 main ●3 │ 󰚰 ↑1 ↓2 │ 14:32
```

---

## Status bar

| Region | Meaning |
| --- | --- |
| `󰖲 work` on `#3d59a1` | Current session (`#S`) |
| `󰘳 PREFIX` on amber | Shown **only while the prefix key is held** (`client_prefix`) |
| `1:vim` dim | Inactive window (`#I:#W`) |
| `2:zsh` cyan on slate, bold | Active window — the only high-contrast element |
| `󰍉 [Z]` purple | The active window's pane is zoomed (`window_zoomed_flag`) |
| `󰻠 18% 󰍛 59%` teal | CPU and memory (`scripts/cpu.sh`) |
| `󰊢 main ●3` blue | Branch and dirty/untracked entries (`scripts/git-read.sh`) |
| `󰚰 ↑1 ↓2` purple | Divergence from upstream (`scripts/git-update.sh`) |
| `14:32` dim | Single clock (`%H:%M`) |

Separators are `│` in `#414868`, the quietest colour in the palette.

Panes follow the same logic: inactive borders are `#292e42` (almost invisible),
the focused pane gets a single crisp `#7aa2f7` border.

---

## Requirements

- **tmux 3.8+** (developed and verified against 3.8; popup styles `-s`/`-S`,
  `-b rounded` and `terminal-features` need a modern tmux)
- **bash** (`/bin/bash` 3.2 on macOS is enough), plus `awk`, `git` and `make`
- A **Nerd Font** for the glyphs (`󰖲 󰘳 󰍉 󰊢 󰚰 󰻠 󰍛`) — this config was built
  with `JetBrainsMono Nerd Font`
- Optional: `lazygit` and `yazi` for the `prefix + g` / `prefix + y` popups

---

## Installation

```bash
git clone <repo-url> ~/.config/tmux
cd ~/.config/tmux
make install
```

`make install` is idempotent and detects the platform:

| Platform | Package manager used |
| --- | --- |
| macOS | Homebrew (`brew install tmux git`) |
| Arch | `pacman` |
| Debian / Ubuntu | `apt-get` |
| NixOS | `nix profile install` (see note below) |
| Fedora / RHEL | `dnf` |

It then symlinks `~/.tmux.conf` → `~/.config/tmux/tmux.conf`, installs the
JetBrainsMono Nerd Font, clones TPM into `~/.tmux/plugins`, installs the
configured plugins, validates everything with `make check`, and reloads a
running server.

Useful switches:

```bash
make install DEPS=0        # skip package installation
make install FONTS=0       # skip the Nerd Font
make install EXTRAS=1      # also install lazygit + yazi
make check                 # validate without changing anything
make clean                 # drop the telemetry cache
make uninstall             # remove the symlinks (plugins stay)
```

**NixOS note.** `make deps` uses `nix profile install` for a quick setup. For a
declarative system, add `tmux git curl unzip` to `environment.systemPackages`
and the font with `fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];`.

If the repo is cloned somewhere other than `~/.config/tmux`, `make link`
symlinks that checkout to `~/.config/tmux`, because the config references the
telemetry scripts by absolute path.

Plugins live in `~/.tmux/plugins` — pinned in `tmux.conf` via
`TMUX_PLUGIN_MANAGER_PATH` so TPM never writes inside the repository.

The repository layout is intentionally flat:

```
~/.config/tmux/
├── Makefile
├── README.md
├── tmux.conf
└── scripts/
    ├── cpu.sh
    ├── git-read.sh
    └── git-update.sh
```

`~/.tmux.conf` is a symlink to `tmux.conf`, so edits are picked up by
`prefix + r` without copying anything.

---

## Keybindings

Prefix is **`Ctrl-a`** (`Ctrl-b` is unbound; press `Ctrl-a` twice to send a
literal `Ctrl-a`).

### Without prefix

| Key | Action |
| --- | --- |
| `M-h` `M-j` `M-k` `M-l` | Move between panes (left/down/up/right) |

### With prefix

| Key | Action |
| --- | --- |
| `Ctrl-h` / `Ctrl-l` | Previous / next window (repeatable) |
| `←` `→` `↑` `↓` | Resize pane (repeatable) |
| `z` | Toggle pane zoom |
| `\|` | Split side-by-side, in the current directory |
| `-` | Split stacked, in the current directory |
| `p` | Floating shell popup in the current directory |
| `P` | Persistent `scratch` session popup |
| `g` | lazygit popup |
| `y` | yazi popup |
| `u` | Force-refresh git telemetry for the current pane |
| `r` | Reload `tmux.conf` |
| `x` / `X` / `Q` | Kill pane / window / session (with confirmation) |

### Copy mode (`prefix + [`)

Vi keys are enabled. `v` starts a selection, `y` copies it to the system
clipboard via `pbcopy` → `wl-copy` → `xclip` → OSC 52, whichever is available.

---

## Telemetry architecture

Every status-bar segment is a script, and every script is designed around one
rule: **the status line must never wait on I/O**.

```
status-right ──> cpu.sh        ──> cached sample (TTL 3s)
             ├─> git-read.sh   ──> cache read only; spawns worker on miss
             └─> git-update.sh ──> cached divergence (TTL 5s); spawns worker on miss
```

Measured on macOS (Apple Silicon):

| Script | Warm | Cold |
| --- | --- | --- |
| `cpu.sh` | ~16 ms | ~58 ms |
| `git-read.sh` | ~14 ms | ~14 ms (+ detached worker) |
| `git-update.sh` | ~17 ms | ~30 ms (worker) |

With `status-interval 2` the whole right side costs roughly 45–50 ms every two
seconds, instead of the ~1.5 s a naive `top -l 2` sample would block for.

### `scripts/cpu.sh`

Prints one line, no ANSI:

```
󰻠 18% 󰍛 59%
```

- **macOS**: one `ps -A -o %cpu=` snapshot normalised by `hw.ncpu`, plus
  `vm_stat` (active + wired + compressor pages, i.e. Activity Monitor's
  "Memory Used"). No `top -l 2`, no `sleep`.
- **Linux**: a `/proc/stat` delta against the previous sample (the raw counters
  are stored in the cache, so no sampling delay is needed) and
  `MemTotal - MemAvailable` from `/proc/meminfo`.
- Cache: `${TMPDIR:-/tmp}/tmux-telemetry-${UID}/cpu`, TTL `TMUX_TELEMETRY_TTL`
  (default `3`).

### `scripts/git-read.sh`

Prints the cached workspace state. It never invokes `git`:

```
󰊢 main ●3     branch main, 3 dirty/untracked entries
󰊢 main        clean
󰊢 –           not inside a repository
```

When the cache is missing or older than `TMUX_GIT_TTL` (default `5`), it serves
the stale value immediately and spawns `git-update.sh` in a detached worker
(stale-while-revalidate).

### `scripts/git-update.sh`

Collects the branch, dirty count and upstream divergence with a **single**
`git status --porcelain=v2 --branch` call, publishes the cache atomically and
prints the sync segment:

```
󰚰 ↑2 ↓1      ahead 2, behind 1
󰚰 ✓          in sync with upstream
󰚰 –          no upstream, detached HEAD, or not a repository
```

Modes:

| Invocation | Behaviour |
| --- | --- |
| `git-update.sh [dir]` | Status-bar mode: print immediately, refresh in background |
| `TMUX_GIT_SYNC=1 git-update.sh [dir]` | Worker mode: sample `git` synchronously (used by the detached spawn) |
| `TMUX_GIT_FORCE=1 git-update.sh [dir]` | Force a foreground refresh (used by `prefix + u`, lazygit, yazi) |

Safety details:

- Writes are atomic (`tmp` + `mv`), so readers never see a half-written cache.
- A `mkdir` lock allows exactly one worker per directory; a lock older than
  30 s is treated as dead and reclaimed.
- Corrupt or partial cache files degrade to a cold sample instead of erroring.
- `GIT_OPTIONAL_LOCKS=0` keeps status polling from touching the index lock.

### Cache location and reset

All telemetry lives in `${TMPDIR:-/tmp}/tmux-telemetry-$(id -u)/`
(`cpu` plus one `git-<cksum>` file per directory).

```bash
rm -rf "${TMPDIR:-/tmp}/tmux-telemetry-$(id -u)"
```

The next status refresh rebuilds everything. `prefix + u` forces a refresh
without deleting anything.

### Optional shell integration

The matching `~/.zshrc` hook makes the branch update the moment you `cd`:

```zsh
update_tmux_git() {
  ~/.config/tmux/scripts/git-update.sh "$PWD" &|
  [[ -n "$TMUX" ]] && tmux refresh-client -S >/dev/null 2>&1
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd update_tmux_git
update_tmux_git
```

Because `git-update.sh` is non-blocking in status mode, the hook returns
instantly; the new sample appears on the next refresh tick.

---

## Popups

All four popups share the same surface treatment, so they read as part of the
terminal rather than a grey overlay:

```tmux
display-popup -E -b rounded -s "bg=#16161e,fg=#7aa2f7" -S "fg=#414868" ...
```

| Flag | Effect |
| --- | --- |
| `-s "bg=#16161e,fg=#7aa2f7"` | Popup body uses the terminal base colour |
| `-b rounded` | Rounded border corners |
| `-S "fg=#414868"` | Dim, palette-matched border |

---

## Customization

### Palette

All colours are declared once at the top of the `PALETTE` section and expanded
into every option, so changing a hue is a one-line edit:

```tmux
base="#16161e"
slate="#292e42"
cyan="#7dcfff"
blue="#7aa2f7"
amber="#e0af68"
purple="#bb9af7"
teal="#73daca"
```

### Status bar

- Windows: `window-status-format` (inactive) and
  `window-status-current-format` (active). The active tab uses a soft slate bed
  with bold cyan text — **no underline**.
- If you are on tmux 3.8+: its default `window-status-current-style` is
  `underscore`, which is why the config sets it to `default`. Removing the
  format attribute alone is not enough.
- Segments: `status-left` and `status-right`. The `#{?client_prefix,…}` left
  block must keep styles in **separate** `#[…]` blocks — a comma inside a
  conditional branch terminates the expression.

### Prefix

Change `set -g prefix C-a` and the matching `bind C-a send-prefix` if you want a
different leader.

---

## Troubleshooting

**Icons render as boxes or blanks.**
Install a Nerd Font (e.g. `JetBrainsMono Nerd Font`) and point your terminal at
it: in Ghostty, `font-family = JetBrainsMono Nerd Font`.

**Colours look 256-colour / washed out.**
Confirm truecolor inside tmux:

```bash
tmux info | grep -i RGB
tmux show -gv default-terminal   # expect: tmux-256color
```

`default-terminal` is read when a pane is created; after changing it, start new
panes (or `tmux kill-server` and reattach).

**Telemetry is empty or stale.**
Run the script by hand — it must print one line and exit 0:

```bash
bash ~/.config/tmux/scripts/cpu.sh
bash ~/.config/tmux/scripts/git-read.sh "$PWD"
```

Then clear the cache and press `prefix + u`.

**Popups still look grey.**
Check that the binding carries the style flags and that tmux supports them:

```bash
tmux list-keys -T prefix | grep display-popup
```

**`prefix + g` / `prefix + y` says the tool is missing.**
Install `lazygit` / `yazi`; the popup prints a message and waits for a key.

**The active tab has an underline.**
Make sure `window-status-current-style` is `default` (see Customization above).

**Status bar feels slow.**
Time a script and raise the TTLs if needed:

```bash
time bash ~/.config/tmux/scripts/cpu.sh
```

`TMUX_TELEMETRY_TTL` (default 3) and `TMUX_GIT_TTL` (default 5) control how
often samples are taken.

---

## Design notes

- **One accent per state.** Cyan means "this is focused", amber means "the
  prefix is armed". Nothing else competes for attention.
- **No duplicated identity.** Hostname, username and a second clock were
  deliberately removed; the bar only shows live operational data.
- **`escape-time 0`** keeps Neovim's modal input immediate.
- **`extended-keys on`** with `csi-u` gives Neovim access to modified keys.
- **Monitor activity without stealing the command line**: windows flag activity
  in amber, but `visual-activity`/`visual-bell` are off.
