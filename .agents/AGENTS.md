
## Android Local Testing Workflow
1. Run local backend if not already running.
2. Run debug APK on phone using `flutter run`.
3. AFTER flutter run has launched the app, establish adb tunnel using `adb reverse tcp:8000 tcp:8000` so the sign-in doesn't fail.
