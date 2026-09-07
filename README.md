# TrackMe: Modern Real-Time Location Tracking Mobile Application

TrackMe is a modern, cross-platform real-time location tracking application rebuilt with **Flutter** (Dart) for the mobile client and **Node.js + Socket.io** for the backend server.

The app allows users to select a Start Point (A) and Destination (B), render optimal driving route polylines using OpenStreetMap / OSRM, and stream real-time GPS coordinates directly to the Node.js backend to synchronize connected clients with live metrics (Distance Left, ETA, Speed, and Heading).

---

## Features & Highlights

- **Modern Material 3 UI/UX**: Dark and Light theme toggle, Google Fonts typography, glassmorphism floating cards, and responsive map controls.
- **Interactive OpenStreetMap Rendering**: Built with `flutter_map` and `latlong2` for fast map tiles with layer switching (Street vs. Dark mode).
- **Live Background & Foreground GPS Streaming**: Uses `geolocator` to stream live device updates (latitude, longitude, speed, heading, and accuracy).
- **Socket.io Real-Time Synchronisation**: Low-latency WebSocket integration via `socket_io_client` sending `locationUpdate` events and receiving `locationBroadcast` broadcasts.
- **Real Place Geocoding & Route Calculation**: Integrates OpenStreetMap Nominatim for geocoding and OSRM for route polylines, with fallback interpolation.
- **In-App Telemetry & Server Config**:
  - Live HUD displaying Distance Left, Remaining ETA, Current Speed, and Heading.
  - Interactive Server Settings modal to change the backend socket URL on the fly (e.g. `http://10.0.2.2:3000` or `http://localhost:3000`).
  - Terminal-style Telemetry Logs drawer to inspect incoming/outgoing socket messages in real time.

---

## Directory Structure

```text
TrackMe/
├── client/                      # Flutter Cross-Platform Client
│   ├── lib/
│   │   ├── main.dart            # Main UI, Map Screen, and State Management
│   │   ├── models/              # TelemetryData schema
│   │   ├── services/            # Location, Socket, and Routing Services
│   │   ├── theme/               # Material 3 Dark/Light Themes & Colors
│   │   └── widgets/             # Reusable UI Components (HUD Cards, Custom Markers, Modals)
│   ├── test/                    # Unit & Widget Tests
│   └── pubspec.yaml             # Flutter Dependencies
├── server/                      # Real-time Node.js Socket Server
│   ├── package.json
│   └── server.js                # Express + Socket.io Server
└── README.md                    # System Guide
```

---

## Prerequisites

1. **Flutter SDK** (3.x or higher) installed and configured on your path.
2. **Node.js** (v16 or higher) and `npm`.
3. An Android Virtual Device (AVD), iOS Simulator, or Web/Desktop environment.

---

## Step 1: Starting the Backend Server

The backend server receives live telemetry coordinates from active tracking devices via WebSockets (`socket.io`) and broadcasts them to listening clients.

```bash
cd server
npm install
npm run dev
```

The server will start listening on `http://localhost:3000` (or `http://10.0.2.2:3000` inside Android Emulators).

---

## Step 2: Running the Flutter Mobile Client

```bash
cd client
flutter pub get
flutter run
```

### Running on Specific Devices / Platforms:

- **Android Emulator**: `flutter run -d android` (Default backend URL set to `http://10.0.2.2:3000`).
- **iOS Simulator**: `flutter run -d ios` (Default backend URL set to `http://localhost:3000`).
- **Web Browser**: `flutter run -d chrome`.

---

## Step 3: Running Tests

To run all unit and widget tests:

```bash
cd client
flutter test
```

---

## Customizing the Server URL in App

If running on a physical phone or remote server, click the **Socket Status Badge** (top right of the app header) to open the **Socket Server Settings** modal and type your host URL (e.g. `http://192.168.1.100:3000`).
