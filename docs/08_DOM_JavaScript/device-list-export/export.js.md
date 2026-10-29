# dom/features/device-list-export/export.js

## 1. このファイルを一言でいうと

DeviceListExport の「操作」ボタンを開き、メニュー内の「CSV出力」をクリックする実操作ファイルです。

## このファイルを変更する典型ケース

- 画面HTML、selector、クリックやスクロールのDOM操作が変わった場合
- PowerShell側の `DomOperations.ps1` から呼ばれるmethod名や戻り値が変わった場合
- contract failure / missing element の診断内容が変わった場合


## 2. このファイルが担当する範囲

画面上の操作ボタンとエクスポートメニュー項目を特定し、クリック可能であることを確認してからクリックします。クリック後は `_lastExportClickResult` に結果を保存し、`contract.js` の `validateExportPostcondition` が後から検証できるようにします。

## 3. PowerShell側 operation との対応

| PowerShell operation | JavaScript method | 目的 |
|---|---|---|
| `ClickTaskButton` | `clickTaskButton` | 操作メニューを開く |
| `IsTaskMenuReady` | `isTaskMenuReady` | エクスポートメニュー項目がクリック可能か待つ |
| `ClickExportMenuItem` | `clickExportMenuItem` | エクスポート項目をクリックする |

## 4. 主な処理の流れ

```text
clickTaskButton
  ├─ resolveTaskButton
  ├─ 候補が1件でなければ throw
  ├─ isClickable を確認
  ├─ scrollIntoView
  ├─ click
  └─ ok:true の結果を返す

clickExportMenuItem
  ├─ resolveExportMenuItem
  ├─ 候補が1件でなければ throw
  ├─ isClickable を確認
  ├─ scrollIntoView
  ├─ click
  ├─ _lastExportClickResult に保存
  └─ ok:true の結果を返す
```

## 5. 失敗条件

| 条件 | 扱い |
|---|---|
| 操作ボタンが0件 | DOM契約違反として throw |
| 操作ボタンが複数 | 誤クリック防止のため throw |
| エクスポート項目が0件 | メニュー未表示または画面変更として throw |
| エクスポート項目が複数 | 誤操作の危険として throw |
| クリック不可 | disabled / hidden の可能性があるため throw |

## 6. JavaScript文法上のポイント

`async` メソッド内で `await this.sleep(...)` を使っています。これはクリック直後にメニュー表示やDOM更新が非同期で起きるためです。PowerShell側の `DomOperations.ps1` では `Await = $true` が設定され、Promiseの完了を待って結果を受け取ります。

## 7. 変更時の注意

`_lastExportClickResult` の保存を消すと、`validateExportPostcondition` が「エクスポートクリックが成立したか」を確認できなくなります。ダウンロードファイルの出現だけで成功判定すると、クリックの失敗とダウンロード待ちタイムアウトの区別がつきにくくなります。
