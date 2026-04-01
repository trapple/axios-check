# axios-check

[axios サプライチェーン攻撃 (2026-03-31)](https://blog.flatt.tech/entry/axios_compromise) の感染有無をチェックするスクリプトです。

## 背景

2026年3月31日、npm パッケージ `axios` のメンテナアカウントが乗っ取られ、マルウェアを含むバージョン (`1.14.1`, `0.30.4`) が公開されました。`npm install` 時に依存パッケージ `plain-crypto-js` の postinstall フックが RAT（遠隔操作トロイの木馬）をドロップします。

## チェック項目

| # | 項目 | 詳細 |
|---|------|------|
| 1 | バックドアファイル | macOS: `/Library/Caches/com.apple.act.mond`、Linux: `/tmp/ld.py`、Windows: `%PROGRAMDATA%\wt.exe` |
| 2 | `plain-crypto-js` | ホームディレクトリ配下の存在確認 |
| 3 | axios 悪性バージョン | `node_modules/axios` が `1.14.1` または `0.30.4` でないか |
| 4 | C2 通信の痕跡 | `sfrclak[.]com` / `142.11.206.73` への接続・DNS キャッシュ・hosts ファイル |

## 使い方

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/trapple/axios-check/main/check_axios_infection.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/trapple/axios-check/main/check_axios_infection.ps1 | iex
```

## 感染が検出された場合

1. 検出されたバックドアファイルを削除
2. axios を安全なバージョンにダウングレード (`npm install axios@1.14.0`)
3. 端末内の全クレデンシャル（SSH 鍵、API トークン等）をローテーション
4. CI/CD 環境のシークレットを確認・ローテーション

## 参考

- [Flatt Security Blog - axios 侵害の詳細分析](https://blog.flatt.tech/entry/axios_compromise)
