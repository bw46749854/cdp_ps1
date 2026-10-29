# dom/features/installed-app-export/detail.js

## 1. このファイルを一言でいうと

端末一覧で行をクリックした後、右側詳細パネルが正しい端末を表示しているかを確認するファイルです。

## このファイルを変更する典型ケース

- 画面HTML、selector、クリックやスクロールのDOM操作が変わった場合
- PowerShell側の `DomOperations.ps1` から呼ばれるmethod名や戻り値が変わった場合
- contract failure / missing element の診断内容が変わった場合


## 2. このファイルが担当する範囲

詳細パネルの表示有無、詳細パネル内の端末名取得、クリックした行と詳細パネルの対象一致を確認します。

## 3. PowerShell側 operation との対応

| PowerShell operation | JavaScript method | 目的 |
|---|---|---|
| `IsDetailPanelReadyFor` | `isDetailPanelReadyFor` | 詳細パネルが対象端末名になったか待つ |
| `ValidateClickedRowContext` | `validateClickedRowContext` | クリックした行と詳細パネルが一致する契約確認 |
| `GetDetailName` | `getDetailAssetName` | 詳細パネル上の端末名を取得する |

## 4. 主な処理の流れ

```text
validateClickedRowContext(dataId, assetName)
  ├─ 選択中の一覧行を取得
  ├─ 詳細パネルの端末名を取得
  ├─ dataId / assetName / detailName の整合性を確認
  └─ 契約結果として返す
```

## 5. なぜこの確認が必要か

一覧行クリック後、画面の詳細パネル更新は非同期です。クリック直後にアプリタブを押すと、前の端末の詳細パネルを操作してしまう危険があります。このファイルは、詳細パネルが対象端末に切り替わったことを確認するための境界です。

## 6. 変更時の注意

`isDetailPanelReadyFor` を単に「詳細パネルが表示されているか」だけにすると、前の端末の詳細パネルを誤って処理する危険があります。必ず端末名一致の確認を残してください。
