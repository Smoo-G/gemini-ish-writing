<#
.SYNOPSIS
    日本語文章の自然さ・語彙レベル・構造をチェックする Linter。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\lint_ja.ps1 .\doc.md
    Get-Content -Raw -Encoding UTF8 .\doc.md | powershell -NoProfile -ExecutionPolicy Bypass -File .\lint_ja.ps1 -Stdin
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [switch]$Stdin,

    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$ErrorRules = @(
    @{ Pattern = '――'; Message = '全角ダッシュの連続（――）は使用禁止' },
    @{ Pattern = '[\uD83C-\uDBFF][\uDC00-\uDFFF]|[\u2600-\u27BF]'; Message = '絵文字は使用禁止' },
    @{ Pattern = '(いい質問ですね|素晴らしい質問|承知しました|以下にまとめます|何かあればお気軽に|お気軽にご連絡)'; Message = '定型的な前置き・締め句は削除する' },
    @{ Pattern = '(この例で意識した点|書くときのポイント|調整のポイント|補足です。|もっと短い版)'; Message = '末尾のメタ解説・書き方の講釈は削除する' },
    @{ Pattern = '(んですね|かなと思いま|ざっくり|ぐっと|まっとうな|空っぽ)'; Message = '砕けすぎた口語・俗語。ビジネス丁寧語または技術用語に置き換える' },
    @{ Pattern = '(?i)(Step\s*\d+|ステップ\s*\d+)'; Message = '手順は「1. 2. 3.」の番号付きリストで書く（Step表記禁止）' },
    @{ Pattern = '(ポイントは\d+つ|理由は\d+つ|以下の\d+点)'; Message = '数を予告してから書かない' },
    @{ Pattern = '(静かに壊れる|解像度を上げ|解像度が高|解像度が低)'; Message = '曖昧な比喩表現は使わず具体的な事象で書く' },
    @{ Pattern = '(することができ|することが可能|という点において)'; Message = '冗長な翻訳調表現。「〜できる」等に簡潔化する' },
    @{ Pattern = '(同じ入れ物|入れ物に入れ|引っかかっ|手を入れ|足を引っ張)'; Message = '専門用語・漢語を曖昧な日常語に言い換えている（例：ストア/ヒットする/変更する/妨げる）' }
)

$WarnRules = @(
    @{ Pattern = '(?<!キャッシュが)(?<!インデックスが)(?<!設定が)(?<!制限が)(?<!ロックが)(?<!ブレーキが)(?<!フィルタが)効(く|き|い|か)'; Message = '曖昧な「効く」の可能性。何がどう改善するか具体的に書けないか確認（仕組みの動作自体を指す場合は許容）' },
    @{ Pattern = '(ほうが安い|ほうが安|安く検出|厚くする|手厚く)'; Message = '比喩的な「安い」「厚く」の可能性。コストが低い／網羅する等の技術表現への言い換えを検討' },
    @{ Pattern = '(ではなく|というより)'; Message = '対比表現の多用に注意。後者だけで意味が通るなら対比を削る' }
)

$SentenceEndRe = [regex]'(です|ます|である|だ|した|ない|れる|られる)[。！？]?$'
$BoldRe = [regex]'\*\*[^*]+\*\*'
$InlineCodeRe = [regex]'`[^`]*`'

function Invoke-LintText {
    param([string]$Text)

    $issues = [System.Collections.Generic.List[pscustomobject]]::new()
    $lines = $Text -split "\r?\n"
    $inCodeBlock = $false
    $recentEndings = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNum = $i + 1
        $stripped = $lines[$i].Trim()

        if ($stripped.StartsWith('```')) {
            $inCodeBlock = -not $inCodeBlock
            continue
        }
        if ($inCodeBlock -or [string]::IsNullOrEmpty($stripped)) {
            continue
        }

        $cleanLine = $InlineCodeRe.Replace($stripped, '')

        foreach ($rule in $ErrorRules) {
            $m = [regex]::Match($cleanLine, $rule.Pattern)
            if ($m.Success) {
                $issues.Add([pscustomobject]@{
                    Line = $lineNum
                    Level = 'ERROR'
                    Message = $rule.Message
                    Snippet = $m.Value
                })
            }
        }

        foreach ($rule in $WarnRules) {
            $m = [regex]::Match($cleanLine, $rule.Pattern)
            if ($m.Success) {
                $issues.Add([pscustomobject]@{
                    Line = $lineNum
                    Level = 'WARN'
                    Message = $rule.Message
                    Snippet = $m.Value
                })
            }
        }

        if ($BoldRe.Matches($cleanLine).Count -ge 3) {
            $snippet = if ($cleanLine.Length -gt 40) { $cleanLine.Substring(0, 40) } else { $cleanLine }
            $issues.Add([pscustomobject]@{
                Line = $lineNum
                Level = 'WARN'
                Message = '1行内の太字が多すぎる（強調箇所を絞る）'
                Snippet = $snippet
            })
        }

        if (-not ($stripped.StartsWith('#') -or $stripped.StartsWith('|') -or $stripped.StartsWith('---'))) {
            $sentences = $cleanLine -split '。'
            foreach ($rawSentence in $sentences) {
                $s = $rawSentence.Trim()
                if ([string]::IsNullOrEmpty($s)) {
                    continue
                }

                if ($s.Length -gt 100 -and $s -notmatch 'http') {
                    $snippet = if ($s.Length -gt 35) { $s.Substring(0, 35) + '...' } else { $s }
                    $issues.Add([pscustomobject]@{
                        Line = $lineNum
                        Level = 'WARN'
                        Message = "1文が長い（$($s.Length)文字）。文の分割を検討"
                        Snippet = $snippet
                    })
                }

                $endMatch = $SentenceEndRe.Match($s)
                if ($endMatch.Success) {
                    $ending = $endMatch.Groups[1].Value
                    $recentEndings.Add($ending)
                    if ($recentEndings.Count -ge 3) {
                        $last3 = @($recentEndings[$recentEndings.Count - 3], $recentEndings[$recentEndings.Count - 2], $recentEndings[$recentEndings.Count - 1])
                        if (($last3 | Select-Object -Unique).Count -eq 1) {
                            $snippet = if ($s.Length -gt 20) { $s.Substring($s.Length - 20) } else { $s }
                            $issues.Add([pscustomobject]@{
                                Line = $lineNum
                                Level = 'WARN'
                                Message = "同じ文末（「$ending」）が3回連続している"
                                Snippet = $snippet
                            })
                        }
                    }
                }
                else {
                    $recentEndings.Clear()
                }
            }
        }
    }

    return $issues
}

if ($Stdin) {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
    $inputText = $reader.ReadToEnd()
}
elseif (-not [string]::IsNullOrWhiteSpace($Path)) {
    $resolved = Resolve-Path -LiteralPath $Path
    $inputText = [System.IO.File]::ReadAllText($resolved.Path, [System.Text.Encoding]::UTF8)
}
else {
    [Console]::Error.WriteLine('エラー: ファイルパスまたは -Stdin を指定してください')
    exit 2
}

$issues = @(Invoke-LintText -Text $inputText)

if ($issues.Count -eq 0) {
    Write-Output 'OK: 指摘事項なし'
    exit 0
}

$errorCount = @($issues | Where-Object { $_.Level -eq 'ERROR' }).Count
$warnCount = @($issues | Where-Object { $_.Level -eq 'WARN' }).Count

foreach ($issue in $issues) {
    Write-Output "L$($issue.Line) [$($issue.Level)] $($issue.Message) (``$($issue.Snippet)``)"
}

Write-Output ''
Write-Output "Summary: $errorCount error(s), $warnCount warning(s)"

if ($errorCount -gt 0 -or ($Strict -and $warnCount -gt 0)) {
    exit 1
}
exit 0
