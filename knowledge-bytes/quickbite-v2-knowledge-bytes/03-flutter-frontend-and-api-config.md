# Byte 3: Flutter screens and API configuration

**Builds on:** Bytes 1–2

## In plain terms
Flutter renders the customer journey and calls the backend for trusted data and actions. The UI can show restaurant cards and cart counts, but it should submit order intent rather than decide final prices itself.

## Relevant paths
- `frontend/lib/screens/restaurant_list_screen.dart`
- `frontend/lib/screens/menu_screen.dart`
- `frontend/lib/screens/cart_screen.dart`
- `frontend/lib/config/app_config.dart`
- `frontend/tests/` (verify exact test filenames in the current checkout)

## API URL behavior
The current project notes indicate that the default API base URL is empty for web deployment, allowing relative `/api/v1/...` requests to pass through Nginx. For local development, an explicit URL may be supplied:
```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```
For Android emulator development, the host machine is commonly reachable as `10.0.2.2`:
```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## What's happening
A relative API path works when the browser and reverse proxy are configured to serve the frontend and proxy API calls on the same origin. A direct localhost URL is useful when running Flutter separately from Docker.

## Why it matters
A wrong API URL can look like an authentication/session failure even when the backend is healthy. After changing build-time defines, rebuild/restart the relevant frontend so the new value is included.
