# FashionNova

Flutter/Dart Android app that tags photographed clothes and generates outfits from your own closet.

<!-- TODO(author): add your own description, screenshots and what you learned. -->

## Stack
Flutter 3 / Dart, Firebase Auth, Cloud Firestore, Firebase Storage, Cloud Functions (Node 20, Gemini proxy with per-user rate limiting), Gemini vision with Hugging Face and ML Kit fallbacks.

## Setup
1. `flutter pub get`
2. Copy `lib/core/config.example.dart` to `lib/core/config.dart` and add your own keys.
3. Add your own `android/app/google-services.json` from a Firebase project.
4. Deploy rules and functions with the Firebase CLI (`firebase deploy`).

Secrets are gitignored and must never be committed.
