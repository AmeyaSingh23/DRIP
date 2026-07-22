## Android Local Testing Workflow
1. Run local backend if not already running.
2. Run debug APK on phone using `flutter run`.
3. AFTER flutter run has launched the app, establish adb tunnel using `C:\Users\ameya\AppData\Local\Android\Sdk\platform-tools\adb.exe reverse tcp:8000 tcp:8000` so the sign-in doesn't fail. Always use this full path to the executable.

## Code Quality Rules
- **Syntax and Brackets:** Always rigorously double-check closing parentheses, brackets, and braces when modifying Flutter widget trees using `multi_replace_file_content` to prevent syntax errors and hot reload failures.

## Shell / Terminal Rules
- **PowerShell Chaining:** Do not use `&&` to chain commands because PowerShell on Windows does not support it by default. Use `;` to chain commands instead (e.g., `git add . ; git commit -m "Msg"`).

## UI/UX Glassmorphism Rules
- **Scroll Blur Fix:** When `BackdropFilter` applies glassmorphic effects (blur) on items inside a scrolling container, it causes visual stuttering, glitching, or becoming transparent if the scrolling elements are translated across separate render boxes. To fix this:
  - DO NOT use `SingleChildScrollView` with a standard column and a floating `AppBar` in the `Scaffold`. 
  - INSTEAD, wrap the page in a `CustomScrollView` with `physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())`.
  - Place a `SliverAppBar` with its own `BackdropFilter` inside the `CustomScrollView`'s slivers, and make the `Scaffold` background completely transparent. This groups the scroll translation in the same compositing layer and solves the blur rendering issue seamlessly while retaining the `BackdropFilter` on list tiles.

## Git & Version Control Rules
- **Explicit Push Confirmation:** NEVER execute `git commit` or `git push` without asking for and receiving explicit approval from the user first. Always allow local testing first.

## Contrast & Theming Rules
- **Pink Backgrounds:** Never use white text inside a baby pink box or background. Always use a dark color (e.g., black or dark maroon) for text on baby pink to maintain readability and contrast.
