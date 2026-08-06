# Hitomi Badayo

<p align="center">
  <a href="README.md"><kbd>English</kbd></a>
  <strong><a href="README.ja.md"><kbd>日本語</kbd></a></strong>
  <a href="README.zh-Hans.md"><kbd>简体中文</kbd></a>
  <a href="README.zh-Hant.md"><kbd>繁體中文</kbd></a>
  <a href="README.ko.md"><kbd>한국어</kbd></a>
</p>

<p>
<img width="687" height="431" alt="sc" src="https://github.com/user-attachments/assets/1c45d909-7818-4dc3-938a-0b6b50293a9e" />
</p>

Hitomi Badayoは、Appleシリコン搭載Mac向けのネイティブダウンロードマネージャーです。キューを中心としたmacOSインターフェースに、配信元ごとの命名規則と保存フォルダ、認証、プレビュー、アーカイブ作成、メディアダウンロード機能をまとめています。

本アプリは、既存のデスクトップダウンローダーで確認できる挙動を参考に、独立してネイティブ実装したものです。元の実行ファイルや逆コンパイルされたバイトコードは、このリポジトリに含まれていません。

バージョン0.5.0では、0.4.2のユーザー向けの挙動、設定、保存データ、ダウンロード結果を維持しながら、保守性向上のためのリファクタリングを完了しました。

## 主な機能

- SwiftUIとAppKitによるmacOSネイティブインターフェース
- 並べ替え、キャンセル、再試行、項目ごとの進捗表示に対応した並行実行キュー
- Hitomi、Pixiv、YouTube、Kemono系アーカイブ、Booru系サイトなどに対応した配信元別ハンドラー
- 配信元別の保存フォルダ、命名テンプレート、ZIP・CBZ作成オプション
- ログインが必要な配信元向けの内蔵ログイン画面とローカルCookie保存
- ループバック接続のSpoofDPIプロキシを使った、任意のアプリ内またはアプリ・ブラウザ向けDPIバイパス
- サムネイルプレビュー、保存結果を開く機能、ライブ録画の安全な停止、クリーンアップ
- 英語、日本語、中国語（簡体字）、中国語（繁体字）、韓国語のインターフェース

配信元サイトの仕様は随時変更されます。あるリリースで動作していたハンドラーでも、サイト側の変更により修正が必要になる場合があります。

## 動作要件

- Appleシリコン搭載Mac（arm64）
- macOS 14 Sonoma以降
- オンラインの配信元への接続と、任意の補助ツールをインストールするためのインターネット接続

## リリース版のインストール

1. 対応するGitHub Releaseから`Hitomi-Badayo-macOS.zip`をダウンロードします。
2. ZIPを展開し、必要に応じて`Hitomi Badayo.app`を「アプリケーション」フォルダへ移動します。
3. 初回起動時はControlキーを押しながらアプリをクリックし、**開く**を選択します。
4. それでもmacOSによりブロックされる場合は、**システム設定 > プライバシーとセキュリティ > このまま開く**を使用します。

配布ビルドはアドホック署名であり、Developer ID署名やAppleの公証は行われていません。Gatekeeperをシステム全体で無効にしないでください。データの保存場所と初回起動時の詳細については、[INSTALLATION.md](docs/INSTALLATION.md)を参照してください。

## ソースからのビルド

Xcode Command Line Toolsをインストールしてから、次のコマンドを実行します。

```sh
xcode-select --install
./build.sh
```

アプリは`Build/Hitomi Badayo.app`に生成されます。出力先を変更する場合は、次のように指定します。

```sh
./build.sh Build-Local
```

ビルドにはmacOSのシステムSDKを使用し、Xcodeプロジェクトは必要ありません。

## 外部ツール

Appleシリコン向けのaria2 1.37.0とSpoofDPI 1.5.3は、ライセンス情報とともに個別の補助プロセスとして同梱されています。yt-dlp、Deno、FFmpeg、ffprobeは任意で、ユーザーが管理ツールのインストールを実行した場合にのみダウンロードされます。YouTubeのJavaScriptチャレンジに対応するため、Denoはyt-dlpへ直接渡されます。詳しくは[THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md)を参照してください。

## DPIバイパス

任意の設定は**設定 > ネットワーク > DPIバイパス**にあり、初期値は**オフ**です。**アプリのみ**は、macOSのプロキシ設定を変更せず、管理者権限も要求せずに、対応するHitomi Badayoのダウンロードを`127.0.0.1`上のSpoofDPIへ接続します。**アプリとブラウザ**は、使用中のmacOSのWebプロキシ（HTTP）とセキュアWebプロキシ（HTTPS）も設定するため、管理者の承認が必要です。このモードを無効にしたとき、またはアプリを終了したときに復元できるよう、変更前のシステムプロキシ設定は保存されます。

手動プロキシの設定は別に保存されます。DPIバイパスと手動プロキシを両方有効にした場合は、ローカルのSpoofDPI経路が優先されます。手動プロキシの設定は保持され、DPIバイパスを無効にすると再び有効になります。

## データとプライバシー

キューの状態、設定、ログインCookie、補助ツール、ダウンロード結果はユーザーのMac内に保存されます。本プロジェクトが運用するテレメトリサービスはありません。ただし、ネットワーク要求はユーザーが選択した配信元サイトや任意のツール提供元へ送信されます。正確な保存場所と制限事項については、[PRIVACY.md](docs/PRIVACY.md)を参照してください。

## 適切な利用について

アクセスおよび保存する権限のあるコンテンツにのみ本アプリを使用してください。ダウンロードに適用される著作権、アカウント、サブスクリプション、配信元サイトの利用規約を確認する責任はユーザーにあります。本プロジェクトは対応サイトと提携しておらず、サイト名や各種マークの権利はそれぞれの所有者に帰属します。

## プロジェクト文書

以下の文書は現在英語で管理されています。

- [INSTALLATION.md](docs/INSTALLATION.md)：インストールと初回起動時の挙動
- [CHANGELOG.md](docs/CHANGELOG.md)：リリース履歴
- [PRIVACY.md](docs/PRIVACY.md)：ローカルデータとネットワーク通信
- [SECURITY.md](docs/SECURITY.md)：脆弱性の報告方法
- [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md)：同梱および任意の外部ツール

## ライセンス

Hitomi Badayoのプロジェクトソースは[MIT License](LICENSE)の下で公開されています。同梱および任意の外部コンポーネントには、[THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md)に記載されたそれぞれのライセンスが引き続き適用されます。
