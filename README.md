# La Maison de Miniso — Phase 1: Auth & Base Setup

This starter contains only Phase 1: the initial `users` migration, FastAPI register/login/me routes, and a Flutter authentication client.

## Local backend

1. Copy `backend/.env.example` to `backend/.env` and replace every placeholder.
2. From `backend`, create and activate a virtual environment.
3. Install dependencies with `pip install -r requirements.txt`.
4. Run `alembic upgrade head`.
5. Run `uvicorn app.main:app --reload --port 8000`.

## Flutter

1. Run `flutter create .` from the `flutter` directory to generate Android platform files without replacing `lib/` or `pubspec.yaml`.
2. Run `flutter pub get`.
3. Start an Android emulator and run `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000`.

For a physical device, replace `10.0.2.2` with the computer's LAN IP and run the API on `0.0.0.0`.

## Security boundary

Only `API_BASE_URL` is supplied to Flutter. Database, JWT, and Cloudinary credentials stay in `backend/.env` and Vercel Environment Variables.
