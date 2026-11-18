---
name: video-analysis
description: >
  Automatically analyze video files when the user shares a .mp4, .mov, .webm, or .avi path.
  Uses vshot to extract frames into a montage grid, then reads the montage for visual analysis.
  Triggers when user asks about a video, shares a video path, or requests video review.
---

# Video Analysis with vshot

When you encounter a video file path (.mp4, .mov, .webm, .avi) and the user wants you to analyze, review, or "watch" it:

## Steps

1. Run vshot to create a montage (pick `--mode` / `--frames` from the guide below):

```bash
"${CLAUDE_PLUGIN_ROOT}/vshot" "<video-path>" --montage --cleanup --mode text --frames 16 --json
```

2. stdout is a single JSON line (human-readable progress goes to stderr). Take the montage path from its `montage` field. Fallback only if JSON parsing fails:

```bash
ls -t "<video-path-without-extension>_vshot/"*_montage_*.jpg | head -1
```

Then use the `Read` tool on the montage image.

3. Analyze what you see and respond to the user's question.

4. If specific moments need a closer look (unreadable text, suspicious frames), re-extract just those times at higher resolution and read the new montage:

```bash
"${CLAUDE_PLUGIN_ROOT}/vshot" "<video-path>" --at 3.5,12,48 --mode detail --montage --cleanup --json
```

## Mode selection guide

- User asks "what's in this video?" → `--mode overview --frames 12`
- User asks to review UI/text content → `--mode text --frames 16`
- User asks about design details → `--mode detail --frames 20`
- Long video (>5 min) → increase `--frames` to 24-30

## Important

- Always use `--cleanup` to remove individual frames after montage creation
- If vshot, ffmpeg, ffprobe, or montage is not available, tell the user to run `/vshot:setup`
- Don't try to analyze video without vshot — you cannot read video files directly
