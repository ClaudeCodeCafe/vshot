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

1. Run vshot to create a montage:

```bash
"${CLAUDE_PLUGIN_ROOT}/vshot" "<video-path>" --montage --cleanup --mode text --frames 16
```

2. Read the generated montage:

```bash
# Find the montage
ls -t "<video-path-without-extension>_vshot/"*_montage_*.jpg | head -1
```

Then use the `Read` tool on the montage image.

3. Analyze what you see and respond to the user's question.

## Mode selection guide

- User asks "what's in this video?" → `--mode overview --frames 12`
- User asks to review UI/text content → `--mode text --frames 16`
- User asks about design details → `--mode detail --frames 20`
- Long video (>5 min) → increase `--frames` to 24-30

## Important

- Always use `--cleanup` to remove individual frames after montage creation
- If vshot, ffmpeg, ffprobe, or montage is not available, tell the user to run `/vshot:setup`
- Don't try to analyze video without vshot — you cannot read video files directly
