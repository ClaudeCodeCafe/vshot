---
name: release
description: vshot の新バージョンをリリースする手順（タグ push → release.yml の自動 bump/Release 作成 → Homebrew tap の formula 更新 → 検証）。Homebrew tap の更新を含む全ステップを最後まで実行すること。
when_to_use: ユーザーが「リリースして」「バージョンアップして」「バージョン上げて」「vX.Y.Z を出して」「新しいバージョンを公開して」「タグ打って」「release」「cut a release」「bump version」などと言ったとき。vshot のリリース・バージョン更新に関する依頼では必ず使う。
---

# vshot リリース手順

リリースは 2 系統の配布先を更新する。**両方終わるまでリリース完了ではない。**

| 配布先 | 更新方法 |
|---|---|
| GitHub Release / Claude Code プラグイン（`vshot`, `plugin.json`, `marketplace.json`） | `v*` タグ push で `.github/workflows/release.yml` が自動処理 |
| Homebrew（`ClaudeCodeCafe/homebrew-tap` の `Formula/vshot.rb`） | **自動化されていない。このスキルの Step 5 で手動更新** |

プロジェクトルートに `cd` してから相対パスで実行する。

## Step 1: 事前チェック

```bash
git fetch origin --tags -q
git status --short                       # 未コミット変更がないこと
git log --oneline -1 origin/main
gh run list --branch main --limit 3      # main 最新コミットの CI が ok であること
git tag --sort=-v:refname | head -1      # 前回のタグ
git log --oneline <前回タグ>..origin/main # 今回含まれる変更
```

- CI が失敗・実行中なら止めてユーザーに報告する。
- バージョン番号を提案する（SemVer: `feat:` を含む → minor、`fix:`/`docs:`/`ci:` のみ → patch、破壊的変更 → 0.x では minor）。
- **タグ push は公開操作なので、バージョン番号をユーザーに確認してから進む**（ユーザーが番号を明示済みならそれで可）。

## Step 2: タグを main HEAD に打って push

```bash
git tag vX.Y.Z origin/main
git push origin vX.Y.Z
```

- タグは必ず main HEAD に打つ。そうでないと release.yml のガードで失敗する。
- 既存タグの手動移動・削除はしない（release.yml が bump コミットへ force 移動する仕様）。

## Step 3: release.yml の完了を待つ

```bash
gh run list --workflow release.yml --limit 1
gh run watch <run-id> --exit-status
```

失敗したら `gh run view <run-id> --log-failed` で原因を調べてユーザーに報告する。

## Step 4: GitHub 側の検証

```bash
git fetch origin --tags -f -q
git log --oneline -2 origin/main                     # "chore: bump version to X.Y.Z [skip ci]" があること
git rev-parse vX.Y.Z^{commit}                        # bump コミットを指していること
git show origin/main:vshot | grep -m1 '^VERSION='
git show origin/main:.claude-plugin/plugin.json | grep version
git show origin/main:.claude-plugin/marketplace.json | grep version   # 2 箇所
gh release list --limit 2                             # vX.Y.Z が Latest
git pull -q --ff-only                                 # ローカル main を同期
```

## Step 5: Homebrew tap を更新（忘れやすい — 必須）

tarball はタグが bump コミットへ移動した**後**（Step 3 完了後）に取得すること。移動前の sha256 は無効になる。

```bash
SHA=$(curl -sL https://github.com/ClaudeCodeCafe/vshot/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256 | cut -d' ' -f1)
echo "$SHA"
```

scratchpad ディレクトリに tap を clone して formula を書き換え、main に直接 push する（tap の慣例: コミットメッセージ `vshot X.Y.Z`）。

```bash
gh repo clone ClaudeCodeCafe/homebrew-tap <scratchpad>/homebrew-tap -- -q
cd <scratchpad>/homebrew-tap
sed -i '' -e "s|refs/tags/v[0-9.]*\.tar\.gz|refs/tags/vX.Y.Z.tar.gz|" \
          -e "s|^  sha256 \".*\"|  sha256 \"$SHA\"|" Formula/vshot.rb
git diff                                  # url と sha256 の 2 行だけが変わっていること
git commit -am "vshot X.Y.Z

Co-Authored-By: Claude <noreply@anthropic.com>"
git push origin main
```

検証:

```bash
gh api repos/ClaudeCodeCafe/homebrew-tap/contents/Formula/vshot.rb -q .content | base64 -d | grep -E 'url|sha256'
```

`brew upgrade vshot` での実インストール確認はユーザー環境を変更するので、実行せず「未検証」として報告し、ユーザーに確認を依頼する。

## Step 6: 報告

- Release URL、bump コミット、タグの指す SHA
- Homebrew tap のコミット
- 未検証項目（プラグイン側の更新、`brew upgrade` の実動作）を明記
