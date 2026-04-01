# axios バージョンチェックスクリプト (Windows / PowerShell)
# ローカルリポジトリとグローバルnpmパッケージから axios の利用状況を検出する
# 参考: https://blog.flatt.tech/entry/axios_compromise

param(
    [string]$SearchRoot = $env:USERPROFILE
)

$Version = "0.2.0"
$badVersions = @("1.14.1", "0.30.4")
$foundCount = 0
$dangerCount = 0
$unpinnedCount = 0

Write-Host "========================================"
Write-Host " axios バージョンチェック v${Version}"
Write-Host " 対象: Windows (PowerShell)"
Write-Host "========================================"
Write-Host ""

function Test-BadVersion($ver) {
    $bare = $ver -replace '^[^0-9]*', ''
    return $bare -in $badVersions
}

function Test-Unpinned($ver) {
    return $ver -match '^[\^~><]' -or $ver -match '[x*]'
}

function Show-Result($location, $version, $source, $suffix = "") {
    $script:foundCount++

    $pinned = ""
    if (Test-Unpinned $version) {
        $script:unpinnedCount++
        $pinned = "未固定"
    }

    if ($suffix -and $pinned) {
        $displayVersion = "${version} (定義のみ・未固定)"
    } elseif ($suffix) {
        $displayVersion = "${version}${suffix}"
    } elseif ($pinned) {
        $displayVersion = "${version} (未固定)"
    } else {
        $displayVersion = $version
    }

    if (Test-BadVersion $version) {
        $script:dangerCount++
        Write-Host "  [危険] " -ForegroundColor Red -NoNewline
        Write-Host "axios@" -NoNewline
        Write-Host "$displayVersion" -ForegroundColor Red
    } elseif ($pinned) {
        Write-Host "  [注意] " -ForegroundColor Yellow -NoNewline
        Write-Host "axios@$displayVersion" -ForegroundColor Yellow
    } else {
        Write-Host "  [安全] " -ForegroundColor Green -NoNewline
        Write-Host "axios@$displayVersion"
    }
    Write-Host "        場所: $location"
    Write-Host "        検出: $source"
    Write-Host ""
}

# --- 1. グローバル npm パッケージの確認 ---
Write-Host "[1/3] グローバル npm パッケージを確認中..." -ForegroundColor Cyan
Write-Host ""

# npm global
if (Get-Command npm -ErrorAction SilentlyContinue) {
    try {
        $npmGlobal = npm ls -g axios --depth=0 --json 2>$null | ConvertFrom-Json
        if ($npmGlobal.dependencies.axios) {
            $version = $npmGlobal.dependencies.axios.version
            $npmPrefix = (npm prefix -g 2>$null).Trim()
            Show-Result $npmPrefix $version "npm global"
        }
    } catch {}
}

# yarn global
if (Get-Command yarn -ErrorAction SilentlyContinue) {
    try {
        $yarnDir = (yarn global dir 2>$null).Trim()
        $yarnAxios = Join-Path $yarnDir "node_modules\axios\package.json"
        if (Test-Path $yarnAxios) {
            $pkg = Get-Content $yarnAxios -Raw | ConvertFrom-Json
            Show-Result $yarnDir $pkg.version "yarn global"
        }
    } catch {}
}

# pnpm global
if (Get-Command pnpm -ErrorAction SilentlyContinue) {
    try {
        $pnpmGlobal = pnpm ls -g axios --json 2>$null | ConvertFrom-Json
        if ($pnpmGlobal.dependencies.axios) {
            $version = $pnpmGlobal.dependencies.axios.version
            $pnpmRoot = (pnpm root -g 2>$null).Trim()
            Show-Result $pnpmRoot $version "pnpm global"
        }
    } catch {}
}

if ($foundCount -eq 0) {
    Write-Host "  グローバルに axios は見つかりませんでした" -ForegroundColor Green
    Write-Host ""
}

# --- 2. ローカルリポジトリの自動検索 ---
Write-Host "[2/3] ローカルリポジトリを検索中... ($SearchRoot)" -ForegroundColor Cyan
Write-Host "       ※ディレクトリの数によっては時間がかかる場合があります"
Write-Host ""

$repoCount = 0
$localStartCount = $foundCount

# ロックファイルを持つプロジェクトを検索
$lockFiles = Get-ChildItem -Path $SearchRoot -Recurse -Depth 5 -ErrorAction SilentlyContinue -Include "package-lock.json", "yarn.lock", "pnpm-lock.yaml" |
    Where-Object { $_.FullName -notmatch '[/\\]node_modules[/\\]' -and $_.FullName -notmatch '[/\\]\.cache[/\\]' }

foreach ($lockFile in $lockFiles) {
    $projectDir = $lockFile.DirectoryName
    $repoCount++

    # node_modules/axios/package.json を確認
    $axiosPkg = Join-Path $projectDir "node_modules\axios\package.json"
    if (Test-Path $axiosPkg) {
        try {
            $pkg = Get-Content $axiosPkg -Raw | ConvertFrom-Json
            if ($pkg.version) {
                Show-Result $projectDir $pkg.version "node_modules"

                # node_modules がある場合でも package.json のバージョン固定状況を確認
                $pkgJson = Join-Path $projectDir "package.json"
                if (Test-Path $pkgJson) {
                    $pkgContent = Get-Content $pkgJson -Raw | ConvertFrom-Json
                    $depSpec = $null
                    if ($pkgContent.dependencies -and $pkgContent.dependencies.axios) {
                        $depSpec = $pkgContent.dependencies.axios
                    }
                    if (-not $depSpec -and $pkgContent.devDependencies -and $pkgContent.devDependencies.axios) {
                        $depSpec = $pkgContent.devDependencies.axios
                    }
                    if ($depSpec -and (Test-Unpinned $depSpec)) {
                        $script:unpinnedCount++
                        Write-Host "  [注意] " -ForegroundColor Yellow -NoNewline
                        Write-Host "axios@$depSpec (未固定)" -ForegroundColor Yellow
                        Write-Host "        場所: $projectDir"
                        Write-Host "        検出: package.json"
                        Write-Host ""
                    }
                }
            }
        } catch {}
        continue
    }

    # node_modules がなくても package.json の dependencies を確認
    $pkgJson = Join-Path $projectDir "package.json"
    if (Test-Path $pkgJson) {
        try {
            $pkgContent = Get-Content $pkgJson -Raw | ConvertFrom-Json
            $depVersion = $null
            if ($pkgContent.dependencies -and $pkgContent.dependencies.axios) {
                $depVersion = $pkgContent.dependencies.axios
            }
            if (-not $depVersion -and $pkgContent.devDependencies -and $pkgContent.devDependencies.axios) {
                $depVersion = $pkgContent.devDependencies.axios
            }
            if ($depVersion) {
                Show-Result $projectDir $depVersion "package.json" " (定義のみ)"
            }
        } catch {}
    }
}

if ($foundCount -eq $localStartCount) {
    Write-Host "  ローカルリポジトリに axios は見つかりませんでした" -ForegroundColor Green
    Write-Host ""
}

# --- 3. 結果サマリ ---
Write-Host "[3/3] サマリ" -ForegroundColor Cyan
Write-Host ""
Write-Host "========================================"
Write-Host "  検索リポジトリ数: $repoCount"
Write-Host "  axios 検出数:     $foundCount"
Write-Host "  未固定バージョン: $unpinnedCount 件"

if ($dangerCount -gt 0) {
    Write-Host ""
    Write-Host "  危険なバージョン:   $dangerCount 件" -ForegroundColor Red
    Write-Host ""
    Write-Host "  悪性バージョン ($($badVersions -join ', ')) が検出されました！" -ForegroundColor Red
    Write-Host "  直ちに安全なバージョンへダウングレードしてください:"
    Write-Host "    npm install axios@1.14.0"
} elseif ($unpinnedCount -gt 0) {
    Write-Host ""
    Write-Host "  未固定のバージョン指定が $unpinnedCount 件あります" -ForegroundColor Yellow
    Write-Host "  バージョンを固定することを推奨します:"
    Write-Host "    npm install axios@1.14.0 --save-exact"
} else {
    Write-Host ""
    Write-Host "  悪性バージョンは検出されませんでした" -ForegroundColor Green
}
Write-Host "========================================"
