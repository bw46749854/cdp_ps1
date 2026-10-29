# dom/features/installed-app-export/actions.js

## 1. このファイルを一言でいうと

端末詳細パネルを閉じるための後始末操作ファイルです。

## このファイルを変更する典型ケース

- 画面HTML、selector、クリックやスクロールのDOM操作が変わった場合
- PowerShell側の `DomOperations.ps1` から呼ばれるmethod名や戻り値が変わった場合
- contract failure / missing element の診断内容が変わった場合


## 2. このファイルが担当する範囲

右側詳細パネルを閉じる操作と、閉じたかどうかの確認を担当します。`InstalledAppExport/internal/RowAction.ps1` の `finally` から呼ばれる後始末に関係します。

## 3. PowerShell側 operation との対応

| PowerShell operation | JavaScript method | 目的 |
|---|---|---|
| `CloseDetailPanel` | `closeDetailPanel` | 詳細パネルの閉じるボタンを押す |
| `IsDetailPanelClosed` | `isDetailPanelClosed` | 詳細パネルが閉じたか確認する |

## 4. なぜ独立ファイルなのか

詳細パネルを閉じる操作は、CSV取得の本処理ではなく、次の行処理へ進むための後始末です。成功時も失敗時も必要になるため、`RowAction.ps1` の finally と対になっています。

```text
1行分の処理
  ├─ 詳細パネルを開く
  ├─ アプリCSVを出す
  └─ finally で closeDetailPanel を呼ぶ
```

## 5. 失敗時の扱い

`CloseDetailPanel` は後始末なので、PowerShell側では致命的な本処理失敗とは少し違う扱いになります。ただし閉じられないと次行の処理に影響するため、ログには必ず診断情報を残す必要があります。

## 6. 変更時の注意

閉じるボタン候補が複数ある場合に先頭をクリックする実装へ変更しないでください。画面内の別の閉じるボタンを押すと、詳細パネル以外の領域を閉じる可能性があります。
