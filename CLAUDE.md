# CLAUDE.md — vshot

Video frame extraction CLI + Claude Code plugin.
One montage grid image lets AI "watch" videos.

## Structure

```
vshot/
├── .claude-plugin/plugin.json   # Plugin manifest
├── vshot                        # CLI tool (single bash script)
├── commands/
│   ├── watch.md                 # /watch command
│   └── setup.md                 # /vshot:setup command
├── skills/
│   └── video-analysis.md        # Auto-trigger video analysis skill
└── CLAUDE.md
```

## CLI Usage

```bash
vshot video.mp4                        # Extract 20 frames
vshot video.mp4 --montage              # Combine into single grid image
vshot video.mp4 --mode text --montage  # Text-readable resolution
vshot video.mp4 --scene --montage      # Scene-change frames only
```

## Plugin Usage

```
/watch video.mp4              # Analyze video
/watch video.mp4 --mode text  # Text-readable mode
/vshot:setup                  # Check dependencies
```

## Tech Stack

- Bash script (macOS bash 3 compatible)
- Dependencies: ffmpeg, ImageMagick

## Rules

- Keep it simple. Core functionality in a single file
- No dependencies beyond ffmpeg and ImageMagick
- Include `Co-Authored-By: Claude` in commit messages (ClaudeCodeCafe org)
