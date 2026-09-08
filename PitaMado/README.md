# PitaMado

PitaMado is a minimal personal macOS menu bar app for moving the frontmost window.

The app can also tile all visible normal windows on the main screen. For example, if 10 windows are open, it lays them out as 5 windows on the top row and 5 windows on the bottom row. It also has grouped layouts for terminal apps and a favorite layout for Chrome, Finder, and terminal windows.

## 1. Xcodeプロジェクトの作り方

このリポジトリには、すでに最小構成のXcodeプロジェクトを作成済みです。

```sh
open PitaMado.xcodeproj
```

新規作成から同じ構成を作る場合は、Xcodeで `macOS > App` を選び、Interfaceを `SwiftUI`、Languageを `Swift` にして作成してください。その後、Dockに出さないため `Info.plist` に `LSUIElement = YES` を追加します。

## 2. 必要なファイル構成

```text
PitaMado.xcodeproj/
PitaMado/
  PitaMadoApp.swift
  AppDelegate.swift
  MenuBarController.swift
  WindowManager.swift
  PermissionManager.swift
  Info.plist
  README.md
```

## 3. 各ファイルの役割

- `PitaMadoApp.swift`: SwiftUIアプリのエントリーポイント
- `AppDelegate.swift`: 起動処理、メニューバー初期化、アクセシビリティ権限チェック
- `MenuBarController.swift`: メニューバーアイコンとメニュー操作
- `WindowManager.swift`: `AXUIElement` によるウインドウ取得、移動、リサイズ、一括整列
- `PermissionManager.swift`: アクセシビリティ権限の確認、要求、システム設定を開く処理
- `Info.plist`: Dock非表示化などのアプリ設定

## 4. Xcodeでの設定内容

- Target: `PitaMado`
- Bundle Identifier: `local.PitaMado`
- Deployment Target: macOS 13.0
- Signing: ローカル実行用のため本格配布設定は不要
- `Info.plist`: `LSUIElement` を `YES` にしてDockに表示しない
- Sandbox: この最小版では有効化していません

## 5. ビルド方法

Xcodeで以下を実行します。

1. `PitaMado.xcodeproj` を開く
2. Schemeで `PitaMado` を選ぶ
3. `Product > Build` を実行
4. `Product > Run` で起動

コマンドラインでビルドする場合は、Xcode本体が選択されている環境で以下を実行します。

```sh
xcodebuild -project PitaMado.xcodeproj -scheme PitaMado -configuration Debug build
```

Command Line Toolsだけが選択されている場合は、必要に応じて以下でXcode本体を選択してください。

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 6. 起動後にアクセシビリティ権限を許可する手順

1. PitaMadoを起動する
2. 初回起動時の権限ダイアログ、またはメニューの `アクセシビリティ権限を開く` を押す
3. `システム設定 > プライバシーとセキュリティ > アクセシビリティ` を開く
4. `PitaMado` を許可する
5. 反映されない場合はPitaMadoを一度終了して再起動する

### アクセシビリティ権限を再ビルド後も維持する

アクセシビリティ権限は、アプリ名だけでなくコード署名の情報にも紐づきます。ad-hoc署名のまま再ビルドすると、macOSが別のアプリとして扱い、許可済みに見えても操作できないことがあります。

`build-local.sh` は、ローカルのコード署名証明書 `PitaMado Local Code Signing` がある場合はそれを使って署名します。証明書がない場合はad-hoc署名に戻します。

証明書はキーチェーンアクセスで作成できます。

1. `キーチェーンアクセス` を開く
2. メニューから `キーチェーンアクセス > 証明書アシスタント > 証明書を作成...` を開く
3. 名前に `PitaMado Local Code Signing` を入力する
4. 証明書のタイプで `コード署名` を選ぶ
5. `自己署名ルート` として作成する
6. `./build-local.sh` で再ビルドする

署名方式を切り替えた直後は、管理者に一度だけアクセシビリティ権限を付け直してもらう必要があります。その後は同じ証明書で署名し続ける限り、再ビルドのたびに許可を付け直す必要はありません。

## 7. 動作確認方法

1. Chrome、Finder、メモなどの通常ウインドウを開く
2. 操作したいウインドウを前面にする
3. メニューバーのPitaMadoアイコンを押す
4. `左半分`、`右半分`、`最大化`、`中央配置` を選ぶ
5. 前面ウインドウが指定位置に移動・リサイズされることを確認する

複数ウインドウをまとめて並べる場合は、Chrome、Finder、メモなどを複数開いた状態で `すべて整列` を選びます。10個の通常ウインドウが見えている場合は、上段5個、下段5個に並びます。

ターミナル系アプリを下部、それ以外を上部に分けたい場合は `ターミナル下・他上` を選びます。Apple Terminal、iTerm2、Warp、Ghostty、Hyper、WezTerm はターミナル扱いにしています。

定番配置にしたい場合は `お気に入り配置` を選びます。Chrome系ブラウザは左 1/3、Finderは右上、ターミナル系アプリは右下に配置します。同じ種類が複数ある場合は、その枠内で均等に並べます。足りないウインドウは自動で開かず、現在表示中の対象ウインドウだけを配置します。

## 8. うまく動かない場合の確認ポイント

- アクセシビリティ権限でPitaMadoが許可されているか
- 許可後にPitaMadoを再起動したか
- 操作対象が通常のリサイズ可能なウインドウか
- フルスクリーン中のウインドウ、システム設定の一部、特殊なパネルではないか
- アプリ側で最小サイズ制限があり、指定サイズまで縮まらないウインドウではないか
- `すべて整列` はメイン画面上に表示されている通常ウインドウを対象にします。最小化中、非表示、フルスクリーン、特殊パネルは対象外です
- `ターミナル下・他上` で使っているターミナルアプリが分類されない場合は、`WindowManager.swift` の `terminalBundleIdentifiers` にBundle IDを追加してください
- `お気に入り配置` で使っているブラウザが分類されない場合は、`WindowManager.swift` の `chromeBundleIdentifiers` にBundle IDを追加してください
- Xcodeから実行している場合、許可対象がビルド済みアプリではなくXcode実行中のアプリとして登録されているか
- Console.appで `PitaMado:` のログが出ていないか
