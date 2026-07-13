# Window Highlight

アクティブウィンドウの外側に色付きの枠を重ねて、現在フォーカスされているウィンドウを見つけやすくするmacOS用メニューバーアプリです。

## 使い方

まずアプリを `/Applications` に配置して起動します。

```sh
make run
```

初回起動時はmacOSのアクセシビリティ許可が必要です。

1. `make run` を実行する
2. システム設定の「プライバシーとセキュリティ」>「アクセシビリティ」を開く
3. `Window Highlight` をONにする
4. アプリを一度終了して、もう一度 `make launch` する

許可後に起動だけやり直す場合:

```sh
make launch
```

枠が見えにくい場合は、太いマゼンタ枠に変更して起動します。

```sh
make high-visibility
```

メニューバーのアイコンをクリックすると、現在どのアプリと座標を対象にしているかを `対象: ...` で確認できます。

設定画面をコマンドで開く場合:

```sh
make open-privacy
```

`Window Highlight` が一覧に出ない場合は、アクセシビリティ画面の `+` から次のアプリを手動で追加してください。

```text
/Applications/WindowHighlight.app
```

ONにできない、またはONにしても効かない場合は、壊れた許可登録を一度消してから入れ直します。

```sh
make reset-accessibility
make run
make open-privacy
```

そのあと `Window Highlight` をONにしてください。

設定を初期化する場合:

```sh
make reset-preferences
```

## 機能

- アクティブウィンドウの周囲に枠を表示
- 枠色を任意に変更
- 枠の太さを変更
- メニューバーから有効・無効を切り替え

## ビルド

```sh
make app
```

生成物は `dist/WindowHighlight.app` に作成されます。

アプリアイコンだけを生成する場合:

```sh
make icon
```

署名状態を確認する場合:

```sh
make verify
```

単体テストを実行する場合:

```sh
make test
```

ビルド、テスト、署名検証、インストール、起動確認をまとめて実行する場合:

```sh
make e2e
```

ローカル開発用のad-hoc署名なので、Developer ID署名や公証は行いません。
