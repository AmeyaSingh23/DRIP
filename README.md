# La Maison de Miniso

A personalized, AI-powered wardrobe and styling application built exclusively for my girlfriend.

## Features

- **Google Authentication**: Secure sign-in using Google OAuth.
- **Wardrobe Management**: Upload images of clothing items. The app automatically removes backgrounds to keep the digital wardrobe clean and aesthetic.
- **AI Stylist & Outfit Generator**: Powered by Gemini, the app acts as a personal stylist. It generates curated outfits from the saved wardrobe items based on user-provided moods, occasions, and current weather conditions.
- **Archive & Restore**: Safely archive older outfits and items without permanently deleting them.
- **Glassmorphic Aesthetic**: A luxurious UI featuring frosted glass effects (glassmorphism), baby pink themes, and deep maroon accents.

## Tech Stack

**Frontend:**
- Flutter (Android/iOS/Web)
- Riverpod (State Management)
- GoRouter (Navigation)
- Google Sign-In

**Backend:**
- Python / FastAPI
- PostgreSQL (Database)
- Alembic (Migrations)
- Cloudinary (Image Hosting & Background Removal)
- Google Gemini API (AI Outfit Generation)

---

## Local Setup

### 1. Backend (FastAPI)
1. Copy `backend/.env.example` to `backend/.env` and replace every placeholder (DB credentials, Cloudinary keys, Gemini keys, etc).
2. From the `backend` directory, create and activate a Python virtual environment.
3. Install dependencies: `pip install -r requirements.txt`
4. Run migrations: `alembic upgrade head`
5. Start the server: `uvicorn app.main:app --reload --port 8000`

### 2. Frontend (Flutter)
1. Navigate to the `flutter` directory.
2. Run `flutter pub get` to install dependencies.
3. To run locally pointing to the local backend:
   ```bash
   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
   ```
   *(For physical devices, replace `10.0.2.2` with your computer's local IP address and run the FastAPI server on `0.0.0.0`)*

## Security boundary

Only the `API_BASE_URL` and OAuth Client IDs are supplied to Flutter. Database credentials, JWT secrets, Gemini API Keys, and Cloudinary keys remain securely stored on the backend environment variables.
