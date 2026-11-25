# gemini-ish-writing

Claude の日本語出力における語彙レベルの統一、認知負荷の低減、および文体の安定化を目的としたルールとスキル（PowerShell 製 Linter 同梱）です。

## 構成

- `CLAUDE.md`: 普段の応答および全体方針に適用する常駐ルール
- `skills/gemini-ish-writing/SKILL.md`: 日本語の文章作成・推敲時に使用するスキル定義
- `skills/gemini-ish-writing/scripts/lint_ja.ps1`: 禁止表現・口語・冗長表現・文末重複・1文の長さを検出する PowerShell Linter（外部依存なし）

## 導入方法（Windows）

`~/.claude/` 配下へファイルを配置します。

```powershell
Copy-Item .\CLAUDE.md "$HOME\.claude\CLAUDE.md"
Copy-Item -Recurse .\skills\gemini-ish-writing "$HOME\.claude\skills\gemini-ish-writing"
```

※既存の `CLAUDE.md` がある場合は、必要に応じて内容をマージしてください。

## Linter 単体での使い方

Windows PowerShell 5.1 および PowerShell 7+ のどちらでも動作します。

```powershell
# ファイルをチェック
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\gemini-ish-writing\scripts\lint_ja.ps1 .\target.md

# WARN でも終了コード 1 を返す厳格モード
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\gemini-ish-writing\scripts\lint_ja.ps1 .\target.md -Strict

# 標準入力からチェック
Get-Content -Raw -Encoding UTF8 .\target.md | powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\gemini-ish-writing\scripts\lint_ja.ps1 -Stdin
```
