#!/bin/bash
# axios バージョンチェックスクリプト (macOS / Linux)
# ローカルリポジトリとグローバルnpmパッケージから axios の利用状況を検出する
# 参考: https://blog.flatt.tech/entry/axios_compromise

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

VERSION="0.2.0"
BAD_VERSIONS=("1.14.1" "0.30.4")
found_count=0
danger_count=0
unpinned_count=0

# 検索ルートディレクトリ（引数があればそれを使用、なければ $HOME）
search_root="${1:-$HOME}"

echo "========================================"
echo " axios バージョンチェック v${VERSION}"
echo " 対象: macOS / Linux"
echo "========================================"
echo ""

is_bad_version() {
    local ver="$1"
    for bad in "${BAD_VERSIONS[@]}"; do
        if [ "$ver" = "$bad" ]; then
            return 0
        fi
    done
    return 1
}

is_unpinned() {
    local ver="$1"
    case "$ver" in
        ^*|~*|\>*|\<*|*x*|*\**) return 0 ;;
        *) return 1 ;;
    esac
}

# バージョン指定からプレフィックスを除去して純粋なバージョンを取得
strip_version_prefix() {
    echo "$1" | sed 's/^[^0-9]*//'
}

print_result() {
    local location="$1"
    local version="$2"
    local source="$3"
    local suffix="${4:-}"

    found_count=$((found_count + 1))

    # バージョン固定チェック（package.json 定義のみが対象）
    local pinned_warn=""
    if is_unpinned "$version"; then
        unpinned_count=$((unpinned_count + 1))
        pinned_warn="・未固定"
    fi

    local display_version="${version}${suffix:+${suffix}}${pinned_warn:+ (${pinned_warn##・})}"
    # suffix と pinned_warn を統合表示
    if [ -n "$suffix" ] && [ -n "$pinned_warn" ]; then
        display_version="${version} (定義のみ・未固定)"
    elif [ -n "$suffix" ]; then
        display_version="${version}${suffix}"
    elif [ -n "$pinned_warn" ]; then
        display_version="${version} (未固定)"
    else
        display_version="${version}"
    fi

    local bare_version
    bare_version=$(strip_version_prefix "$version")

    if is_bad_version "$bare_version"; then
        danger_count=$((danger_count + 1))
        echo -e "  ${RED}[危険]${NC} axios@${RED}${display_version}${NC}"
    elif [ -n "$pinned_warn" ]; then
        echo -e "  ${YELLOW}[注意]${NC} axios@${YELLOW}${display_version}${NC}"
    else
        echo -e "  ${GREEN}[安全]${NC} axios@${display_version}"
    fi
    echo "        場所: ${location}"
    echo "        検出: ${source}"
    echo ""
}

# --- 1. グローバル npm パッケージの確認 ---
echo -e "${CYAN}[1/3] グローバル npm パッケージを確認中...${NC}"
echo ""

# npm global
if command -v npm &>/dev/null; then
    global_axios=$(npm ls -g axios --depth=0 --json 2>/dev/null || true)
    if echo "$global_axios" | grep -q '"axios"'; then
        version=$(echo "$global_axios" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"' || true)
        if [ -n "$version" ]; then
            npm_prefix=$(npm prefix -g 2>/dev/null)
            print_result "$npm_prefix" "$version" "npm global"
        fi
    fi
fi

# yarn global
if command -v yarn &>/dev/null; then
    yarn_global_dir=$(yarn global dir 2>/dev/null || true)
    if [ -n "$yarn_global_dir" ] && [ -f "$yarn_global_dir/node_modules/axios/package.json" ]; then
        version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$yarn_global_dir/node_modules/axios/package.json" | head -1 | grep -o '"[^"]*"$' | tr -d '"' || true)
        if [ -n "$version" ]; then
            print_result "$yarn_global_dir" "$version" "yarn global"
        fi
    fi
fi

# pnpm global
if command -v pnpm &>/dev/null; then
    pnpm_global_axios=$(pnpm ls -g axios --json 2>/dev/null || true)
    if echo "$pnpm_global_axios" | grep -q '"axios"'; then
        version=$(echo "$pnpm_global_axios" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"' || true)
        if [ -n "$version" ]; then
            pnpm_root=$(pnpm root -g 2>/dev/null)
            print_result "$pnpm_root" "$version" "pnpm global"
        fi
    fi
fi

if [ "$found_count" -eq 0 ]; then
    echo -e "  ${GREEN}グローバルに axios は見つかりませんでした${NC}"
    echo ""
fi

# --- 2. ローカルリポジトリの自動検索 ---
echo -e "${CYAN}[2/3] ローカルリポジトリを検索中... (${search_root})${NC}"
echo "       ※ディレクトリの数によっては時間がかかる場合があります"
echo ""

repo_count=0
local_start_count=$found_count

# package-lock.json / yarn.lock / pnpm-lock.yaml を持つプロジェクトを検索
while IFS= read -r -d '' lockfile; do
    project_dir=$(dirname "$lockfile")

    # node_modules 内のロックファイルはスキップ
    case "$project_dir" in
        */node_modules/*) continue ;;
    esac

    repo_count=$((repo_count + 1))

    # node_modules/axios/package.json を確認（存在チェックと読み込みを統合）
    axios_pkg="$project_dir/node_modules/axios/package.json"
    version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$axios_pkg" 2>/dev/null | head -1 | grep -o '"[^"]*"$' | tr -d '"' || true)
    if [ -n "$version" ]; then
        print_result "$project_dir" "$version" "node_modules"
        continue
    fi

    # node_modules がなくても package.json の dependencies / devDependencies を確認
    pkg_json="$project_dir/package.json"
    dep_version=$(grep -o '"axios"[[:space:]]*:[[:space:]]*"[^"]*"' "$pkg_json" 2>/dev/null | head -1 | grep -o '"[^"]*"$' | tr -d '"' || true)
    if [ -n "$dep_version" ]; then
        print_result "$project_dir" "$dep_version" "package.json" " (定義のみ)"
    fi

    # node_modules がある場合でも package.json のバージョン固定状況を確認
    if [ -n "$version" ]; then
        pkg_json="$project_dir/package.json"
        dep_spec=$(grep -o '"axios"[[:space:]]*:[[:space:]]*"[^"]*"' "$pkg_json" 2>/dev/null | head -1 | grep -o '"[^"]*"$' | tr -d '"' || true)
        if [ -n "$dep_spec" ] && is_unpinned "$dep_spec"; then
            unpinned_count=$((unpinned_count + 1))
            echo -e "  ${YELLOW}[注意]${NC} axios@${YELLOW}${dep_spec} (未固定)${NC}"
            echo "        場所: ${project_dir}"
            echo "        検出: package.json"
            echo ""
        fi
    fi
done < <(find "$search_root" \
    -maxdepth 5 \
    \( -name "node_modules" -o -name ".cache" -o -name "Library" \) -prune -o \
    \( -name "package-lock.json" -o -name "yarn.lock" -o -name "pnpm-lock.yaml" \) \
    -print0 2>/dev/null || true)

if [ "$found_count" -eq "$local_start_count" ]; then
    echo -e "  ${GREEN}ローカルリポジトリに axios は見つかりませんでした${NC}"
    echo ""
fi

# --- 3. 結果サマリ ---
echo -e "${CYAN}[3/3] サマリ${NC}"
echo ""
echo "========================================"
echo "  検索リポジトリ数: ${repo_count}"
echo "  axios 検出数:     ${found_count}"
echo "  未固定バージョン: ${unpinned_count} 件"

if [ "$danger_count" -gt 0 ]; then
    echo ""
    echo -e "  ${RED}危険なバージョン:   ${danger_count} 件${NC}"
    echo ""
    echo -e "  ${RED}悪性バージョン (${BAD_VERSIONS[*]}) が検出されました！${NC}"
    echo "  直ちに安全なバージョンへダウングレードしてください:"
    echo "    npm install axios@1.14.0"
elif [ "$unpinned_count" -gt 0 ]; then
    echo ""
    echo -e "  ${YELLOW}未固定のバージョン指定が ${unpinned_count} 件あります${NC}"
    echo "  バージョンを固定することを推奨します:"
    echo "    npm install axios@1.14.0 --save-exact"
else
    echo ""
    echo -e "  ${GREEN}悪性バージョンは検出されませんでした${NC}"
fi
echo "========================================"
