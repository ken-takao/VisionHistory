# TestFlight release runbook

このプロジェクトは、初回のApple側設定後に次の1コマンドで内部TestFlightへ配信する構成です。

```sh
bundle exec fastlane ios beta
```

laneはRust/Swiftテスト、XCFramework生成、XcodeGen、最新TestFlight build番号の取得、署名、アップロード、Apple側の処理完了まで行います。内部グループはApp Store Connect側で「Automatically distribute new builds」を有効にして自動配信します。

## Apple側で一度だけ行うこと

1. Apple Developer Programの契約が有効で、Account Holderが最新契約へ同意済みか確認する。
2. Explicit App ID `ai.kiokurelay.demo` をTeam `UJ293X328U`に登録する。
3. App Store ConnectでApp recordを作る。
   - Platform: iOS
   - Name: KIOKU RELAY
   - Primary language: Japanese
   - Bundle ID: `ai.kiokurelay.demo`
   - SKU: `kioku-relay-ios`
4. Users and AccessでAdminまたはApp Manager権限のApp Store Connect API keyを作り、`.p8`をリポジトリ外へ保存する。署名profileの自動管理に必要なCertificates, Identifiers & Profilesへのアクセスも有効にする。
5. 内部テスターグループを作る。自動配信を有効にすると処理後の配信が最短になる。
6. App Store Connectの申告項目を用意する。
   - Privacy Policy URLとApp Privacy回答
   - 年齢レーティング
   - Beta Feedback Email
   - 外部テストを行う場合はBeta App Description、審査連絡先、Review Notes、必要なら失効しないデモアカウント

Bundle IDとSKUはApp record作成後の変更に制約があります。別IDを使う場合は、初回buildをアップロードする前に`KIOKU_BUNDLE_ID`と`project.yml`を同じ値へ変更してください。

## ローカル設定

```sh
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_KEY_PATH="/absolute/path/AuthKey_YOUR_KEY_ID.p8"
```

クラウド機能も含む短期デモを配る場合だけ、次を作成します。

```sh
cp Config/ReleaseSecrets.xcconfig.example Config/ReleaseSecrets.xcconfig
```

このファイルはGit対象外ですが、値は配布バイナリから抽出できます。配信終了後に全資格情報を失効し、本番配信前にはBFFへ移してください。

## 検証と配信

```sh
bundle check
bundle exec fastlane ios verify
bundle exec fastlane ios beta
```

任意の上書き:

```sh
KIOKU_BUILD_NUMBER=2 KIOKU_WHAT_TO_TEST="今回の確認項目" bundle exec fastlane ios beta
```

## App Store Connect申告の下書き

- Tracking: No
- Data linked to identity: No（現行デモはアカウントを持たない）
- Purposes: App Functionality
- Data types: Photos or Videos、Audio Data、Other User Content
- Required-reason API: File Timestamp / `C617.1`（アプリコンテナ内のQdrantファイル管理）
- Export compliance: 現行用途は標準TLSとローカル検索で、`ITSAppUsesNonExemptEncryption = NO`。暗号機能や依存関係を追加した場合は再判定する。

実際の送信・保持条件が変わった場合は、`PrivacyInfo.xcprivacy`とApp Privacy回答も同時に更新してください。

## 外部テスト

外部TestFlightにはBeta App Description、Feedback Email、審査連絡先、Review Notes、必要ならデモアカウントが必要です。最初の外部buildはTestFlight App Review対象のため、内部配信のように時刻を保証できません。
