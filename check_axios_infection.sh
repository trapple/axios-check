#!/bin/bash
# axios サプライチェーン攻撃 感染チェックスクリプト (macOS / Linux)
# 参考: https://blog.flatt.tech/entry/axios_compromise

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

infected=false

VERSION="0.1.1"

echo "========================================"
echo " axios 感染チェックスクリプト v${VERSION}"
echo " 対象: macOS / Linux"
echo "========================================"
echo ""

os_type="$(uname -s)"

# --- 1. バックドアファイルの存在確認 ---
echo "[1/5] バックドアファイルの確認..."

if [ "$os_type" = "Darwin" ]; then
    backdoor="/Library/Caches/com.apple.act.mond"
    if [ -f "$backdoor" ]; then
        echo -e "  ${RED}[危険] バックドアファイルを検出: ${backdoor}${NC}"
        infected=true
    else
        echo -e "  ${GREEN}[安全] macOS バックドアファイルは見つかりませんでした${NC}"
    fi
else
    backdoor="/tmp/ld.py"
    if [ -f "$backdoor" ]; then
        echo -e "  ${RED}[危険] バックドアファイルを検出: ${backdoor}${NC}"
        infected=true
    else
        echo -e "  ${GREEN}[安全] Linux バックドアファイルは見つかりませんでした${NC}"
    fi
fi

# --- 2. plain-crypto-js パッケージの確認 ---
echo ""
echo "[2a/5] plain-crypto-js パッケージの確認..."

found_plain_crypto=false
while IFS= read -r -d '' dir; do
    echo -e "  ${RED}[危険] plain-crypto-js を検出: ${dir}${NC}"
    found_plain_crypto=true
    infected=true
done < <(find "$HOME" -path "*/node_modules/plain-crypto-js" -type d -print0 2>/dev/null || true)

if [ "$found_plain_crypto" = false ]; then
    echo -e "  ${GREEN}[安全] plain-crypto-js は見つかりませんでした${NC}"
fi

# --- 2b. Lockfile 内の plain-crypto-js 参照確認 ---
echo ""
echo "[2b/5] Lockfile 内の plain-crypto-js 参照確認..."

found_lockfile_ref=false
while IFS= read -r -d '' lockfile; do
    # node_modules 内のファイルはスキップ
    case "$lockfile" in
        */node_modules/*) continue ;;
    esac
    if grep -q "plain-crypto-js" "$lockfile" 2>/dev/null; then
        echo -e "  ${RED}[危険] Lockfile に plain-crypto-js の参照を検出: ${lockfile}${NC}"
        found_lockfile_ref=true
        infected=true
    fi
done < <(find "$HOME" \( -name "package-lock.json" -o -name "yarn.lock" -o -name "pnpm-lock.yaml" \) -print0 2>/dev/null || true)

if [ "$found_lockfile_ref" = false ]; then
    echo -e "  ${GREEN}[安全] Lockfile に plain-crypto-js の参照は見つかりませんでした${NC}"
fi

# --- 3. axios の悪性バージョン確認 ---
echo ""
echo "[3/5] axios の悪性バージョン確認..."

found_bad_axios=false
while IFS= read -r -d '' pkg; do
    version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$pkg" 2>/dev/null | head -1 | grep -o '"[^"]*"$' | tr -d '"' || true)
    if [ "$version" = "1.14.1" ] || [ "$version" = "0.30.4" ]; then
        echo -e "  ${RED}[危険] 悪性バージョン axios@${version} を検出: ${pkg}${NC}"
        found_bad_axios=true
        infected=true
    fi
done < <(find "$HOME" -path "*/node_modules/axios/package.json" -print0 2>/dev/null || true)

if [ "$found_bad_axios" = false ]; then
    echo -e "  ${GREEN}[安全] 悪性バージョンの axios は見つかりませんでした${NC}"
fi

# --- 4. C2サーバへの通信確認 ---
echo ""
echo "[4/5] C2サーバへの通信確認..."

c2_found=false
c2_indicators=("sfrclak.com" "142.11.206.73")

# netstat の結果を一度だけ取得
netstat_output=$(netstat -an 2>/dev/null || true)

for indicator in "${c2_indicators[@]}"; do
    # DNS キャッシュ確認 (macOS)
    if [ "$os_type" = "Darwin" ]; then
        if dscacheutil -cachedump 2>/dev/null | grep -q "$indicator" 2>/dev/null; then
            echo -e "  ${RED}[危険] DNSキャッシュに C2 インジケータを検出: ${indicator}${NC}"
            c2_found=true
            infected=true
        fi
    fi

    # ネットワーク接続確認
    if echo "$netstat_output" | grep -q "$indicator"; then
        echo -e "  ${RED}[危険] アクティブな接続で C2 インジケータを検出: ${indicator}${NC}"
        c2_found=true
        infected=true
    fi

    # /etc/hosts 確認
    if grep -q "$indicator" /etc/hosts 2>/dev/null; then
        echo -e "  ${YELLOW}[注意] /etc/hosts に C2 インジケータを検出: ${indicator}${NC}"
        c2_found=true
    fi
done

if [ "$c2_found" = false ]; then
    echo -e "  ${GREEN}[安全] C2サーバへの通信の痕跡は見つかりませんでした${NC}"
fi

# --- 結果サマリ ---
echo ""
echo "========================================"
if [ "$infected" = true ]; then
    echo -e "${RED}[結果] 感染の痕跡が検出されました！${NC}"
    echo ""
    echo "以下の対応を直ちに実施してください:"
    echo "  1. 検出されたバックドアファイルを削除"
    echo "  2. axios を安全なバージョンにダウングレード (npm install axios@1.14.0)"
    echo "  3. 端末内の全クレデンシャル（SSH鍵, API トークン等）をローテーション"
    echo "  4. CI/CD 環境のシークレットを確認・ローテーション"
else
    echo -e "${GREEN}[結果] 感染の痕跡は検出されませんでした${NC}"
fi
echo "========================================"
