# PitaMado

[English README](README_EN.md)

PitaMado は、キーボードとマウスでの作業を整える、軽量なmacOSメニューバー型ウインドウマネージャーです。Dockには表示せず、macOSのアクセシビリティAPIを使って通常のアプリウインドウを移動・リサイズします。

> 初期段階の個人プロジェクトです。ローカル作業用として利用できますが、現時点では公証済み・Sandbox対応の配布版ではありません。

## 主な機能

- 前面のウインドウを左半分、右半分、中央、最大化へ配置
- 現在の画面で表示中のウインドウを整列
- ターミナル系アプリを他のウインドウの下に配置
- Chrome系ブラウザ、Finder、ターミナル用の「お気に入り配置」
- 別のmacOSデスクトップ（Space）のウインドウは動かさず、お気に入り配置で不足したウインドウも新規作成しない

### お気に入り配置

画面を左1/3と右2/3に分けます。

![PitaMadoのお気に入り配置: 左にChrome、右上にFinder、右下にTerminal](docs/images/favorite-layout.png)

- Chrome系ブラウザ: 左1/3、縦いっぱい
- Finder: 右上。Finderを2枚表示する場合、画面全体の幅に対して左20%・右46%（右側2/3の中では約30:70）
- ターミナル: 右下。ターミナルを2枚表示する場合、均等に2分割

Chrome系としてGoogle Chrome、Edge、Brave、Vivaldi、Arcを、ターミナル系としてTerminal、iTerm2、Warp、Ghostty、Hyper、WezTermを認識します。

## 必要環境

- macOS 13以降
- PitaMadoへのアクセシビリティ権限
- ソースからビルドする場合はSwiftコンパイラまたはXcode

## ビルドと起動

```sh
git clone https://github.com/ohta-keiichi/PitaMado.git
cd PitaMado
./build-local.sh
open build/PitaMado.app
```

`build-local.sh` は、`PitaMado Local Code Signing` というローカル証明書があればそれで署名します。なければad-hoc署名を使います。同じローカル証明書を使い続けると、再ビルド後もmacOSのアクセシビリティ権限を維持しやすくなります。

Xcodeからビルドする場合は、`PitaMado.xcodeproj` を開き、`PitaMado` スキームを実行してください。

## アクセシビリティ権限

ウインドウを配置する前に、PitaMadoへの権限を許可してください。

`システム設定 > プライバシーとセキュリティ > アクセシビリティ > PitaMado`

署名IDを変更した場合は、権限を付け直したあとにアプリを終了・再起動してください。

## プライバシー

PitaMadoはmacOSのアクセシビリティAPIを通じてローカルで動作します。分析、ネットワーク通信、サーバー機能は含みません。

## プロジェクト構成

- `PitaMado/` — Swiftソースとアプリのリソース
- `PitaMado.xcodeproj/` — Xcodeプロジェクト
- `build-local.sh` — 再現可能なローカルビルド・署名スクリプト
- `アプリ概要.md` — 日本語のプロダクト説明

## ライセンス

[MIT License](LICENSE)で公開しています。
