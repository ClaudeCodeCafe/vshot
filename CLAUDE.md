# CLAUDE.md — vshot

Video frame extraction CLI + Claude Code plugin.
MP4 → モンタージュグリッド1枚で AI に動画を「見せる」。

## 構成

```
vshot/
├── .claude-plugin/plugin.json   # プラグインマニフェスト
├── vshot                        # CLI ツール本体
├── commands/
│   ├── watch.md                 # /watch コマンド
│   └── setup.md                 # /vshot:setup コマンド
├── skills/
│   └── video-analysis.md        # 動画分析スキル
└── CLAUDE.md
```

## CLI 使い方

```bash
vshot video.mp4                        # 20フレーム抽出
vshot video.mp4 --montage              # 1枚のグリッド画像に
vshot video.mp4 --mode text --montage  # 文字が読めるサイズで
```

## プラグイン使い方

```
/watch video.mp4              # 動画を分析
/watch video.mp4 --mode text  # テキスト読み取りモード
/vshot:setup                  # 依存チェック
```

## 技術スタック

- Bash スクリプト（macOS bash 3 互換）
- 依存: ffmpeg, ImageMagick

## ルール

- シンプルを維持。コア機能は1ファイル
- ffmpeg と ImageMagick 以外の依存を増やさない
- コミットメッセージに `Co-Authored-By: Claude` 含めない
