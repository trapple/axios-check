# axios-check

[axios サプライチェーン攻撃 (2026-03-31)](https://blog.flatt.tech/entry/axios_compromise) の感染有無チェック・バージョン確認スクリプトです。

## 背景

2026年3月31日、npm パッケージ `axios` のメンテナアカウントが乗っ取られ、マルウェアを含むバージョン (`1.14.1`, `0.30.4`) が公開されました。`npm install` 時に依存パッケージ `plain-crypto-js` の postinstall フックが RAT（遠隔操作トロイの木馬）をドロップします。

## スクリプト一覧

| スクリプト | 用途 | バージョン |
|---|---|---|
| `check_axios_infection.sh` | 感染チェック (macOS / Linux) | v0.1.1 |
| `check_axios_infection.ps1` | 感染チェック (Windows) | v0.1.2 |
| `check_axios_version.sh` | axios バージョン確認 (macOS / Linux) | v0.3.0 |
| `check_axios_version.ps1` | axios バージョン確認 (Windows) | v0.3.0 |

## 1. 感染チェック (`check_axios_infection`)

端末がマルウェアに感染していないかを確認します。

### チェック項目

| # | 項目 | 詳細 |
|---|------|------|
| 1 | バックドアファイル | macOS: `/Library/Caches/com.apple.act.mond`、Linux: `/tmp/ld.py`、Windows: `%PROGRAMDATA%\wt.exe`, `%TEMP%\6202033.vbs`, `%TEMP%\6202033.ps1` |
| 2a | `plain-crypto-js` | node_modules 配下の存在確認 |
| 2b | Lockfile 参照 | `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` 内の `plain-crypto-js` 参照 |
| 3 | axios 悪性バージョン | `node_modules/axios` が `1.14.1` または `0.30.4` でないか |
| 4 | C2 通信の痕跡 | `sfrclak[.]com` / `142.11.206.73` への接続・DNS キャッシュ・hosts ファイル |

### 使い方

macOS / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/trapple/axios-check/main/check_axios_infection.sh | bash
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/trapple/axios-check/main/check_axios_infection.ps1 | iex
```

## 2. バージョン確認 (`check_axios_version`)

ローカルリポジトリとグローバルパッケージから axios の利用状況を一括確認します。

### 機能

- **グローバルパッケージ確認** — npm / yarn / pnpm のグローバルインストールをチェック
- **ローカルリポジトリ自動検索** — ホームディレクトリ配下のプロジェクトを自動検出し、axios のバージョンを確認
- **悪性バージョン検出** — `1.14.1` / `0.30.4` を `[危険]` として警告
- **脆弱バージョン検出** — [CVE-2026-40175](https://github.com/advisories/GHSA-fvcv-3m26-pcqx) の影響を受ける `< 1.15.0` を `[脆弱]` として警告し、`npm update axios` を促します

### 使い方

macOS / Linux（デフォルトは `$HOME` 配下を検索）:

```bash
curl -fsSL https://raw.githubusercontent.com/trapple/axios-check/main/check_axios_version.sh | bash
```

検索ディレクトリを指定:

```bash
curl -fsSL https://raw.githubusercontent.com/trapple/axios-check/main/check_axios_version.sh | bash -s /path/to/repos
```

Windows（デフォルトは `%USERPROFILE%` 配下を検索）:

```powershell
irm https://raw.githubusercontent.com/trapple/axios-check/main/check_axios_version.ps1 | iex
```

検索ディレクトリを指定（ダウンロードして実行）:

```powershell
.\check_axios_version.ps1 -SearchRoot "D:\repos"
```

## 感染が検出された場合

1. 検出されたバックドアファイルを削除
2. axios を安全なバージョンにダウングレード (`npm install axios@1.14.0`)
3. 端末内の全クレデンシャル（SSH 鍵、API トークン等）をローテーション
4. CI/CD 環境のシークレットを確認・ローテーション

## 参考

- [Flatt Security Blog - axios 侵害の詳細分析](https://blog.flatt.tech/entry/axios_compromise)
