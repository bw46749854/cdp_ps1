# Mock pages

実在の管理画面の代わりに、自動化ジョブのDOM契約（`main/dom/features/`）を満たす画面を返すモックです。
画面に表示されるデータはすべて架空です。

## 構成

| パス | 内容 |
|---|---|
| `server.ps1` | `site\` 配下を `http://localhost:8080/` で配信する静的サーバ（Windows PowerShell 5.1 / HttpListener） |
| `start_mock_server.bat` | `server.ps1` の起動用 |
| `site/example-security/` | ExampleSecurity Cloud Service「センサー / デバイス (既定グループ)」画面 |
| `site/example-asset/` | ExampleAsset「端末一覧」画面 |

## 使い方

1. `mock\start_mock_server.bat` を実行して、モックサーバを起動する。
2. ルート直下の `ExampleSecurity.lnk` または `ExampleAsset.lnk` から、CDP（ポート9222）を有効にした Edge で画面を開く。
3. 対応するジョブのbatを実行する。

| 画面 | URL | ジョブ | 起動bat |
|---|---|---|---|
| ExampleSecurity | `http://localhost:8080/example-security/` | `WeeklyScanTargetSync` | `週次作業_スキャン対象整合.bat` |
| ExampleAsset | `http://localhost:8080/example-asset/` | `MonthlyInstallReport` | `月次作業_インストールレポート.bat` |

2つの画面を別タブで同時に開いていても、各ジョブはページ識別で操作対象のタブを1つに絞り込みます。

## 画面ごとの再現内容

### ExampleSecurity（センサー / デバイス一覧）

- 左ナビの「センサー」、グループツリーの「デバイス (既定グループ)」、件数表示「センサー: 40」
- 「操作」メニューの「CSV出力」で、一覧をBOM付きUTF-8のCSV（`sensor_devices.csv`）としてダウンロード
- 端末一覧は仮想スクロールで描画し、表示範囲付近の行だけをDOMに置く
- 行のチェックで「スキャン」メニュー（端末共通）の「手動スキャンの開始」が有効になる
- 一部の端末は、前回操作のチェックが残っている状態で表示される

日付は現在日時からの相対値で生成します。手動スキャン完了日と最終通信日時の差は、判定閾値（7日）の前後に分布させています。

### ExampleAsset（端末一覧）

- `#contents.asset`、パンくず「端末一覧」、件数表示（`assetList.totalCount`）
- 一覧は、固定列側（選択・端末名、`#asset-grid_fixed`）と通常列側（OS・利用者など、`#asset-grid`）に分かれ、同じ `data-id` の行を両側に描画する。縦スクロールは両側で同期する
- 端末名セルのクリックで右側の詳細パネルが開く（読み込み待ちを再現するため、少し遅れて内容が表示される）
- 詳細パネルの「インストール済みアプリ」タブで、アプリ一覧と「CSV出力」ボタンを表示
- CSVのファイル名は `app_list_YYYYMMDD.csv` で、端末名を含まない（端末名はジョブ側のリネームで付ける）

導入日は現在日付からの相対値で生成し、前月導入のアプリを必ず含めます。
1台（`PCXX-01-006`）だけ導入日が空のアプリを含み、LastMonthInstallExtract ジョブの失敗一覧に載る例になっています。

## 動作確認の結果

ヘッドレス Edge で2画面を開いた状態で、両ジョブを実行して確認しました。

| ジョブ | 結果 |
|---|---|
| `WeeklyScanTargetSync` | CSV出力 → 40件を判定（ON 18件 / OFF 22件）→ チェック状態整合 40/40件成功、正常終了 |
| `MonthlyInstallReport` | 12台のCSVを取得 → 前月導入 20件を抽出、導入日なし1件を失敗一覧に出力、正常終了 |
