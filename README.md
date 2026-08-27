# KIOKU RELAY

カメラで見た場面を、あとから日本語で検索できるiPhone向けデモです。

- Apple Vision / Natural Language: 画像・テキストを端末内で特徴量化
- Qdrant Edge: 端末内のベクトル検索（Rust C ABIブリッジ）
- OpenAI Responses API: 代表フレームだけを日本語で構造化説明
- Neo4j Aura Query API: 物・場所・観測時刻の関係をグラフとして保存
- Shisa.ai: 保存した記憶の日本語音声読み上げ

## 起動

必要環境はXcode 26、XcodeGen、Rust toolchainです。

```sh
cp Config/DebugSecrets.xcconfig.example Config/DebugSecrets.xcconfig
xcodegen generate
open KIOKURelay.xcodeproj
```

`Config/DebugSecrets.xcconfig`へデモ用の認証情報を設定します。このファイルはGit対象外ですが、値はDebugアプリへ組み込まれるため配布には使わないでください。

Qdrant EdgeのXCFrameworkを更新する場合:

```sh
EdgeBridge/scripts/build-xcframework.sh
```

## データフロー

1. カメラ映像は表示中だけ処理し、数秒ごとにキーフレームを選びます。
2. Vision Feature Printを端末内で生成し、Qdrant Edgeへ保存・類似検索します。
3. ユーザーがクラウド補完を有効にした時だけ、代表画像1枚をOpenAIへ送ります。
4. OpenAIの説明をAppleの日本語埋め込みで検索可能にし、Neo4jへ観測関係を同期します。
5. 詳細画面ではShisa.aiによる日本語読み上げを利用できます。

通常のバックグラウンド中はカメラ撮影を続けません。画面を離れるかアプリが非アクティブになるとセッションを停止します。

## セキュリティ

この構成は開発者端末だけで使う短期デモ用です。デモ終了後はOpenAI/ShisaキーとNeo4j資格情報を失効してください。本番版ではすべてのクラウド認証情報をBFFまたはSecret Managerへ移し、iPhoneには配布しません。

## TestFlight

Apple側の初回設定後は、検証と内部TestFlight配信をFastlaneで実行できます。

```sh
bundle exec fastlane ios verify
bundle exec fastlane ios beta
```

初回設定、必要な環境変数、外部テスト時の追加作業は
[`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md)を参照してください。
