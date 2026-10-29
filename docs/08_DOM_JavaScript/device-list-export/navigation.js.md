# dom/features/device-list-export/navigation.js

## 1. このファイルを一言でいうと

DeviceListExport の前提画面へ到達するために、左ナビゲーション上の「センサー」と「デバイス (既定グループ)」を安全に特定するファイルです。

## このファイルを変更する典型ケース

- 画面HTML、selector、クリックやスクロールのDOM操作が変わった場合
- PowerShell側の `DomOperations.ps1` から呼ばれるmethod名や戻り値が変わった場合
- contract failure / missing element の診断内容が変わった場合


## 2. このファイルが担当する範囲

画面上のナビゲーション要素を探し、候補が1件だけかどうかを診断します。クリック自体は主にPowerShell側のWorkflowや別メソッドの呼び出し順に組み込まれます。

## 3. 主なメソッド

| メソッド | 役割 |
|---|---|
| `resolveSensorNavigation` | 「センサー」ナビゲーションを特定する |
| `resolveDeviceDefaultNavigation` | 「デバイス (既定グループ)」ナビゲーションを特定する |

## 4. 探索方針

最初に安定した属性を使います。たとえば `data-components` や `data-label` のような属性です。これで見つからない場合に、テキスト、title、role、nav配下などの条件で候補を探します。

```text
明示的 selector で探索
  ├─ 1件なら ok
  ├─ 複数なら ambiguous として ok=false
  └─ 0件なら fallback 探索
        ├─ テキストや title を確認
        ├─ nav / menu / tree の範囲に限定
        └─ visible候補が1件なら ok
```

## 5. なぜ候補数を厳密に見るのか

ナビゲーションは画面遷移の起点です。候補が複数あると、DOM上の先頭要素をクリックしただけで別メニューへ遷移する危険があります。そのため、このファイルは「最初に見つかったもの」ではなく「意味的に一意に特定できたもの」だけを成功扱いします。

## 6. 変更時の注意

selector を追加するときは、必ず `visible` 判定と候補数の診断を残してください。`querySelector` で最初の1件を返すだけにすると、画面変更時に誤クリックを検出できなくなります。
