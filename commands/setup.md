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

If everything is installed, say:

```
All good! Use /watch <video-path> to analyze videos.
```
