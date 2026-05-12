# vshot

[![CI](https://github.com/ClaudeCodeCafe/vshot/actions/workflows/ci.yml/badge.svg)](https://github.com/ClaudeCodeCafe/vshot/actions/workflows/ci.yml)

**Video frame extraction for AI.** One montage image. One `Read()` call. Your AI can now watch videos.

<p align="center">
  <img src="docs/montage-example.jpg" alt="vshot montage example" width="720">
  <br>
  <em>12 frames from a 62-second video → 6×2 grid, 140KB. Portrait auto-detected.</em>
</p>

## The Problem

> AI assistants can read images but can't watch videos. Feeding 20 separate screenshots burns tokens and loses context.

| Without vshot | With vshot |
|---|---|
| Manually screenshot frames | `vshot video.mp4 --montage` |
| Feed 20 images → 20,000+ tokens | Feed 1 montage → ~1,500 tokens |
| No timestamps, no context | Timestamped grid, full flow visible |
| Tedious every time | One command, done |

## How It Works

```
MP4 → ffmpeg extracts frames → timestamps burned in → ImageMagick tiles into grid → 1 image

┌──────┬──────┬──────┬──────┬──────┬──────┐
│ 0:00 │ 0:05 │ 0:11 │ 0:17 │ 0:22 │ 0:28 │
├──────┼──────┼──────┼──────┼──────┼──────┤
│ 0:34 │ 0:39 │ 0:45 │ 0:51 │ 0:56 │ 1:02 │
└──────┴──────┴──────┴──────┴──────┴──────┘
              → montage.jpg (one image!)
```

Aspect ratio is auto-detected. Portrait (9:16) and landscape (16:9) videos are handled correctly — no stretching.

## Modes

| Mode | Resolution | Use case |
|------|-----------|----------|
| `overview` | 480×270 | "What's in this video?" |
| `text` | 960×540 | Read UI text, code, terminals |
| `detail` | 1280×720 | Design review, pixel inspection |

## Install

### Option A: Homebrew (Recommended)

```bash
brew tap ClaudeCodeCafe/tap
brew install vshot
```

Installs vshot with ffmpeg and ImageMagick as dependencies. Done.

### Option B: Claude Code Plugin

```bash
/plugin marketplace add ClaudeCodeCafe/vshot
/plugin install vshot@vshot
```

Then use directly:

```
/watch video.mp4
/watch video.mp4 --mode text
/vshot:setup
```

### Option C: Manual

```bash
# Prerequisites
brew install ffmpeg imagemagick

# Clone and link
git clone https://github.com/ClaudeCodeCafe/vshot.git
ln -s "$(pwd)/vshot/vshot" /usr/local/bin/vshot

# Or curl
curl -o /usr/local/bin/vshot https://raw.githubusercontent.com/ClaudeCodeCafe/vshot/main/vshot
chmod +x /usr/local/bin/vshot
```

## Usage

```bash
# Create montage (most common)
vshot video.mp4 --montage

# Text-readable montage
vshot video.mp4 --montage --mode text

# Just extract frames (no grid)
vshot video.mp4 --frames 20

# Every 5 seconds
vshot video.mp4 --montage --interval 5

# High detail, more frames
vshot video.mp4 --montage --mode detail --frames 30

# Clean up individual frames after montage
vshot video.mp4 --montage --cleanup

# Scene detection — only extract frames where the visual content changes
vshot video.mp4 --scene --montage

# Stricter scene detection (fewer frames)
vshot video.mp4 --scene 0.5 --montage
```

### Options

| Flag | Description | Default |
|------|------------|---------|
| `--montage` | Combine into single grid image | off |
| `--mode` | overview / text / detail | overview |
| `--frames N` | Number of frames | 20 |
| `--interval N` | Extract every N seconds | — |
| `--scene [N]` | Extract only scene-change frames (0.0-1.0) | 0.3 |
| `--output DIR` | Custom output directory | `<video>_vshot/` |
| `--cleanup` | Remove frames after montage | off |
| `--no-timestamps` | Skip timestamp overlay | — |

## Scene Detection

`--scene` uses ffmpeg's scene change detection to extract only the frames that matter — skipping duplicates and static content.

<table>
<tr>
<th>vshot video.mp4 --montage (uniform)</th>
<th>vshot video.mp4 --scene --montage (smart)</th>
</tr>
<tr>
<td><img src="docs/montage-example.jpg" width="360"></td>
<td><img src="docs/montage-scene.jpg" width="360"></td>
</tr>
<tr>
<td>12 frames, 140KB — includes duplicates</td>
<td>5 frames, 76KB — only key moments</td>
</tr>
</table>

Same video. Fewer frames. Zero redundancy.

## Token Efficiency

| Approach | Images to read | ~Tokens | File size |
|----------|---------------|---------|-----------|
| Manual screenshots | 5-10 | 5,000-10,000 | 5-10 MB |
| Frame dump | 20 | 20,000+ | 2+ MB |
| **vshot montage** | **1** | **~1,500** | **~156 KB** |

One montage. ~97% fewer tokens. Zero effort.

## Dependencies

| Dependency | Install | Required for |
|---|---|---|
| ffmpeg | `brew install ffmpeg` | Frame extraction (always) |
| ImageMagick | `brew install imagemagick` | Montage grid (`--montage` only) |

## License

MIT
