## Android Local Testing Workflow
1. Run local backend if not already running.
2. Run debug APK on phone using `flutter run`.
3. AFTER flutter run has launched the app, establish adb tunnel using `C:\Users\ameya\AppData\Local\Android\Sdk\platform-tools\adb.exe reverse tcp:8000 tcp:8000` so the sign-in doesn't fail. Always use this full path to the executable.

## Code Quality Rules
- **Syntax and Brackets:** Always rigorously double-check closing parentheses, brackets, and braces when modifying Flutter widget trees using `multi_replace_file_content` to prevent syntax errors and hot reload failures.
