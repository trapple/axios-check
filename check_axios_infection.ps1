# axios サプライチェーン攻撃 感染チェックスクリプト (Windows / PowerShell)
# 参考: https://blog.flatt.tech/entry/axios_compromise

$Version = "0.1.2"
$infected = $false

Write-Host "========================================"
Write-Host " axios 感染チェックスクリプト v${Version}"
Write-Host " 対象: Windows (PowerShell)"
Write-Host "========================================"
Write-Host ""

# --- 1. バックドアファイルの存在確認 ---
Write-Host "[1/5] バックドアファイルの確認..."

$backdoorFiles = @(
    (Join-Path $env:PROGRAMDATA "wt.exe"),
    (Join-Path $env:TEMP "6202033.vbs"),
    (Join-Path $env:TEMP "6202033.ps1")
)

$backdoorFound = $false
foreach ($backdoor in $backdoorFiles) {
    if (Test-Path $backdoor) {
        Write-Host "  [危険] バックドアファイルを検出: $backdoor" -ForegroundColor Red
        $infected = $true
        $backdoorFound = $true
    }
}

if (-not $backdoorFound) {
    Write-Host "  [安全] バックドアファイルは見つかりませんでした" -ForegroundColor Green
}

# --- 2. plain-crypto-js パッケージの確認 ---
Write-Host ""
Write-Host "[2a/5] plain-crypto-js パッケージの確認..."

$foundPlainCrypto = $false
$searchPaths = @($env:USERPROFILE)

foreach ($searchPath in $searchPaths) {
    $dirs = Get-ChildItem -Path $searchPath -Directory -Filter "plain-crypto-js" -Recurse -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        Write-Host "  [危険] plain-crypto-js を検出: $($dir.FullName)" -ForegroundColor Red
        $foundPlainCrypto = $true
        $infected = $true
    }
}

if (-not $foundPlainCrypto) {
    Write-Host "  [安全] plain-crypto-js は見つかりませんでした" -ForegroundColor Green
}

# --- 2b. Lockfile 内の plain-crypto-js 参照確認 ---
Write-Host ""
Write-Host "[2b/5] Lockfile 内の plain-crypto-js 参照確認..."

$foundLockfileRef = $false
$lockFiles = Get-ChildItem -Path $env:USERPROFILE -Recurse -ErrorAction SilentlyContinue -Include "package-lock.json", "yarn.lock", "pnpm-lock.yaml" |
    Where-Object { $_.FullName -notmatch '[/\\]node_modules[/\\]' }

foreach ($lockFile in $lockFiles) {
    if (Select-String -Path $lockFile.FullName -Pattern "plain-crypto-js" -Quiet -ErrorAction SilentlyContinue) {
        Write-Host "  [危険] Lockfile に plain-crypto-js の参照を検出: $($lockFile.FullName)" -ForegroundColor Red
        $foundLockfileRef = $true
        $infected = $true
    }
}

if (-not $foundLockfileRef) {
    Write-Host "  [安全] Lockfile に plain-crypto-js の参照は見つかりませんでした" -ForegroundColor Green
}

# --- 3. axios の悪性バージョン確認 ---
Write-Host ""
Write-Host "[3/5] axios の悪性バージョン確認..."

$foundBadAxios = $false
$badVersions = @("1.14.1", "0.30.4")

foreach ($searchPath in $searchPaths) {
    $pkgFiles = Get-ChildItem -Path $searchPath -Filter "package.json" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -match '[/\\]node_modules[/\\]axios$' }

    foreach ($pkgFile in $pkgFiles) {
        try {
            $pkg = Get-Content $pkgFile.FullName -Raw | ConvertFrom-Json
            if ($pkg.version -in $badVersions) {
                Write-Host "  [危険] 悪性バージョン axios@$($pkg.version) を検出: $($pkgFile.FullName)" -ForegroundColor Red
                $foundBadAxios = $true
                $infected = $true
            }
        } catch {
            # JSON パースエラーは無視
        }
    }
}

if (-not $foundBadAxios) {
    Write-Host "  [安全] 悪性バージョンの axios は見つかりませんでした" -ForegroundColor Green
}

# --- 4. C2サーバへの通信確認 ---
Write-Host ""
Write-Host "[4/5] C2サーバへの通信確認..."

$c2Found = $false
$c2Indicators = @("sfrclak.com", "142.11.206.73")

# アクティブな接続を確認
$connections = netstat -an 2>$null
foreach ($indicator in $c2Indicators) {
    if ($connections -match [regex]::Escape($indicator)) {
        Write-Host "  [危険] アクティブな接続で C2 インジケータを検出: $indicator" -ForegroundColor Red
        $c2Found = $true
        $infected = $true
    }
}

# DNS キャッシュ確認
try {
    $dnsCache = Get-DnsClientCache -ErrorAction SilentlyContinue
    foreach ($indicator in $c2Indicators) {
        $match = $dnsCache | Where-Object { $_.Entry -like "*$indicator*" -or $_.Data -like "*$indicator*" }
        if ($match) {
            Write-Host "  [危険] DNSキャッシュに C2 インジケータを検出: $indicator" -ForegroundColor Red
            $c2Found = $true
            $infected = $true
        }
    }
} catch {
    # Get-DnsClientCache が使えない環境は無視
}

# hosts ファイル確認
$hostsFile = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
if (Test-Path $hostsFile) {
    $hostsContent = Get-Content $hostsFile -Raw -ErrorAction SilentlyContinue
    foreach ($indicator in $c2Indicators) {
        if ($hostsContent -match [regex]::Escape($indicator)) {
            Write-Host "  [注意] hosts ファイルに C2 インジケータを検出: $indicator" -ForegroundColor Yellow
            $c2Found = $true
        }
    }
}

if (-not $c2Found) {
    Write-Host "  [安全] C2サーバへの通信の痕跡は見つかりませんでした" -ForegroundColor Green
}

# --- 結果サマリ ---
Write-Host ""
Write-Host "========================================"
if ($infected) {
    Write-Host "[結果] 感染の痕跡が検出されました！" -ForegroundColor Red
    Write-Host ""
    Write-Host "以下の対応を直ちに実施してください:"
    Write-Host "  1. 検出されたバックドアファイルを削除"
    Write-Host "  2. axios を安全なバージョンにダウングレード (npm install axios@1.14.0)"
    Write-Host "  3. 端末内の全クレデンシャル (SSH鍵, API トークン等) をローテーション"
    Write-Host "  4. CI/CD 環境のシークレットを確認・ローテーション"
} else {
    Write-Host "[結果] 感染の痕跡は検出されませんでした" -ForegroundColor Green
}
Write-Host "========================================"
