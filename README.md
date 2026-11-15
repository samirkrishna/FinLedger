# FinLedger

Offline-first Android personal finance ledger. Flutter UI + SQLite (sqflite), with a small Kotlin Android SMS receiver. No backend, cloud account, analytics SDK, or network permission is included.

## Features in this starter build
- Local SQLite transaction ledger
- Manual income and expense entry
- Month navigation and income/expense/net cash-flow summary
- Category summary
- Android SMS inbox import (up to 5,000 most recent inbox messages)
- Incoming SMS receiver queues likely financial transaction messages locally
- Duplicate protection using bank reference when available, otherwise a message/date/amount fingerprint
- OTP-like messages are excluded from the incoming SMS queue

## Important limitations
- SMS formats differ by bank and may change. The parser is deliberately conservative and should be tested against redacted sample messages from the banks you use.
- Automatic SMS reading requires Android SMS permissions. Google Play restricts SMS permissions; publication requires policy eligibility and approval. Sideloading also requires the user to grant permissions.
- iOS does not provide equivalent unrestricted SMS inbox access.
- This starter version does not yet reconcile balances, classify every bank format, or encrypt the SQLite database. Do not treat the calculated cash flow as the actual bank balance.
- No app can recover SMS messages deleted before import. Make regular exports/backups before changing phones; an encrypted backup feature is a follow-up task.

## Build APK with GitHub Actions
1. Create a private GitHub repository and upload the contents of this folder.
2. Push to `main`, or open **Actions → Build FinLedger APK → Run workflow**.
3. When the workflow completes, download the `FinLedger-Android-APK` artifact.
4. Extract `app-release.apk` and install it on your Android phone. Android will ask you to allow installation from that source.

The workflow creates Flutter's Android project scaffolding, restores the custom Kotlin SMS receiver and manifest, runs analysis, and builds the release APK.

## Local development build
Install Flutter stable and Android Studio/Android SDK, then run:

```bash
flutter create . --platforms=android --org com.finledger --project-name finledger
cp android_overrides/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
mkdir -p android/app/src/main/kotlin/com/finledger/finledger
cp android_overrides/MainActivity.kt android/app/src/main/kotlin/com/finledger/app/MainActivity.kt
cp android_overrides/BankSmsReceiver.kt android/app/src/main/kotlin/com/finledger/app/BankSmsReceiver.kt
flutter pub get
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`.
\n\n## Build fix (Flutter 3.50)\n- Updated deprecated color opacity and dropdown initial-value APIs.\n- Replaced the generated starter widget test that referenced a nonexistent `MyApp` and `material_ui` package.\n- Made SMS queue table creation idempotent to avoid a first-launch schema collision if an SMS arrives before the app opens.\n