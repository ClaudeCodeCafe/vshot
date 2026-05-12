---
description: Analyze a video file by extracting frames and creating a visual montage
argument-hint: '<video-path> [--mode overview|text|detail] [--frames N]'
allowed-tools: Bash, Read, AskUserQuestion
---

# /watch — Video analysis for AI

Extract frames from a video file and analyze the content visually.

## Steps

1. Parse the arguments. The first argument is the video file path. Optional flags:
   - `--mode`: overview (default), text (for reading UI/text), detail (high-res)
   - `--frames`: number of frames (default: 16)

2. Check dependencies:

```bash
command -v ffmpeg && command -v montage
```

If either is missing, tell the user:
```
Missing dependencies. Install with: brew install ffmpeg imagemagick
```
And stop.

3. Run vshot to create a montage:

```bash
"${CLAUDE_PLUGIN_ROOT}/vshot" "$VIDEO_PATH" --montage --cleanup --mode "$MODE" --frames "$FRAMES"
```

4. Find the generated montage file:

```bash
ls -t "${VIDEO_PATH%.*}_vshot/"*_montage.jpg | head -1
```

5. Use the `Read` tool to read the montage image.

6. Analyze the video content based on what you see in the montage:
   - Describe the overall flow/structure of the video
   - Note any text, UI elements, or visual content visible
   - If it appears to be a CCC (Claude Code Cafe) video, comment on the layout, MeiMei character, terminal content
   - Provide constructive feedback if the user seems to be reviewing the video

Keep your analysis concise but thorough. Focus on what's actually visible in the frames.
