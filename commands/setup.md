---
description: Check vshot dependencies and readiness
allowed-tools: Bash, AskUserQuestion
---

# /vshot:setup — Dependency check

Check whether all dependencies for vshot are installed.

Run these checks:

```bash
echo "=== vshot setup check ==="
echo ""

# Check vshot
if [ -x "${CLAUDE_PLUGIN_ROOT}/vshot" ]; then
  echo "✅ vshot      $(grep 'VERSION=' "${CLAUDE_PLUGIN_ROOT}/vshot" | head -1 | cut -d'"' -f2)   ready"
else
  echo "❌ vshot      not found"
fi

# Check ffmpeg
if command -v ffmpeg &>/dev/null; then
  echo "✅ ffmpeg     $(ffmpeg -version 2>&1 | head -1 | awk '{print $3}')   installed"
else
  echo "❌ ffmpeg     not installed"
fi

# Check ffprobe
if command -v ffprobe &>/dev/null; then
  echo "✅ ffprobe    installed"
else
  echo "❌ ffprobe    not installed (comes with ffmpeg)"
fi

# Check ImageMagick montage
if command -v montage &>/dev/null; then
  echo "✅ montage    $(montage --version 2>&1 | head -1 | awk '{print $3}')   installed"
else
  echo "❌ montage    not installed (ImageMagick)"
fi

echo ""
```

Present the results to the user.

If ffmpeg or montage is missing, use `AskUserQuestion` to ask:

- Option 1: "Install missing dependencies (Recommended)" — run `brew install ffmpeg imagemagick`
- Option 2: "Skip for now"

If the user chooses install, run:

```bash
brew install ffmpeg imagemagick
```

Then rerun the check to confirm.

## CLI shim (optional)

The plugin binary lives under a versioned path (`~/.claude/plugins/cache/vshot/vshot/<version>/vshot`) that changes on every update, which makes it awkward to call from shells and scripts.

Check whether `vshot` is already reachable:

```bash
command -v vshot || echo "vshot not on PATH"
```

If it is not on PATH, use `AskUserQuestion` to ask:

- Option 1: "Install vshot shim to ~/.local/bin (Recommended)" — a tiny wrapper that resolves the latest installed plugin version at runtime, so it survives plugin updates
- Option 2: "Skip"

If the user chooses install, run:

```bash
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/vshot" <<'SHIM'
#!/bin/bash
# vshot shim — resolves the latest plugin-installed version at runtime
BASE="$HOME/.claude/plugins/cache/vshot/vshot"
LATEST=$(ls -d "$BASE"/*/ 2>/dev/null | sort -V | tail -1)
if [ -z "$LATEST" ] || [ ! -x "${LATEST}vshot" ]; then
  echo "vshot shim: plugin not found under $BASE (reinstall with: /plugin install vshot@vshot)" >&2
  exit 1
fi
exec "${LATEST}vshot" "$@"
SHIM
chmod +x "$HOME/.local/bin/vshot"
"$HOME/.local/bin/vshot" --version
```

Then check that `~/.local/bin` is on PATH:

```bash
case ":$PATH:" in *":$HOME/.local/bin:"*) echo "PATH ok" ;; *) echo "PATH missing ~/.local/bin" ;; esac
```

If PATH is missing it, tell the user to add this line to their shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Wrap up

If everything is installed, say:

```
All good! Use /watch <video-path> to analyze videos.
```
