# 🏛️ Campus Square (Mobile App)

**The All-in-One Verified Campus Ecosystem**  
Replacing chaotic WhatsApp & Telegram groups with a structured, domain-verified platform for university students.

## 📖 About The Project

**Campus Square** is a comprehensive, mobile-first ecosystem designed exclusively for university and college campuses. Built with **Flutter**, it tackles the fragmentation of student life by consolidating official announcements, peer-to-peer discussions and commerce, department-wise academic resources, hierarchical group chats (Hubs & Teams), real-time messaging, and community trust into a single, seamless application.

Access is strictly governed by domain-locked authentication (e.g., `@institute.ac.in`), ensuring a secure, verified environment free from spam and external noise.

## ✨ Core Modules & Features

The mobile frontend is organized into several key operational modules:

### 📢 1. The Square (Community Hub)

- **Swipable Category Feed**: Smooth horizontal swipe navigation across post categories (`All`, `Random`, `Events`, `Notices`, `Lost & Found`, `Complaints`, `Ride Pool`, `Roommate`).
- **Inline Quick Compose**: Fixed bottom message input for fast community discussion posting.
- **Smart Roommate Finder**: Algorithmic matching based on structured lifestyle preferences (Dietary Preference, Sleep Schedule, Study Habits).
- **Separated Voting & Sorting**: Independent upvote/downvote counters with sorting choices (`Created At` vs `Most Voted`) for discussions and complaints.
- **Lost & Found & Ride Pooling**: Peer-to-peer coordination with direct messaging links.

### 🛒 2. The Bazaar (Marketplace)

- **Verified Buy/Sell/Rent**: Localized campus marketplace for textbooks, electronics, stationery, and dorm furniture.
- **Listing Management**: Real-time status toggles (Mark as Sold, Save Favorites) and custom image upload support.
- **One-Tap Chat Connection**: Directly message sellers via pre-filled item inquiry templates.

### 🗄️ 3. The Vault (Academic Ledger)

- **Department Repositories**: Structured, permanent file organization categorized by department, semester (1–8), and resource type (PYQs, Notes, Syllabus, Other).
- **Resource Curation**: Upvote/downvote ranking algorithm that highlights quality study material and deprioritizes outdated content.
- **Document Preview & In-App Viewers**: Native PDF preview, external browser launcher, and cached cloud document viewing.

### 💬 4. Real-Time Chat & Campus Hub

- **Discord-Style Hubs**: Join official Clubs and peer-run Study Groups. Each Hub has a dedicated dashboard containing a main "General Chat" and multiple nested "Teams/Channels" managed by Hub Admins and Team Leads. Pull-to-refresh enabled across all group lists.
- **Categorized Inbox**: The Messaging screen uses a tabbed layout, separating private 1-on-1 "Chats" (DMs) from large-scale "Hubs & Teams".
- **WebSocket Connection**: Real-time DMs and group/department conversation streams.
- **Real-Time Moderation**: WebSocket connections actively drop or restrict participants the moment they are removed from a group, blocked by a Hub Admin, or globally suspended, ensuring instant enforcement without requiring an app restart.
- **Messaging Utilities**: Unread message boundary dividers, delivery/read receipts, typing indicators, image/file attachments, message editing, and 15-minute deletion rules.
- **Customization**: Customizable chat wallpapers and local group icon selection.
- **Visual Hierarchies**: Chat bubbles feature distinct visual badges (🛡️ Hub Admin, ⭐ Team Lead, ✔️ Staff) to establish authority and trust in large groups.

### 🔔 5. Push & Local Notifications

- **Targeted FCM Notifications**: Automated alerts for new Bazaar items, Vault uploads, urgent announcements, and direct messages.
- **Interactive Notification Center**: In-app bell icon history sheet for reviewing past announcements and system notices.

### 📅 6. Cloud-Synced Timetable & Attendance

- **Subject-wise Dashboards**: Create subjects, set target attendance policies (e.g., 75%), and track live metrics like total classes attended, missed, and how many more classes are "safe to miss".
- **Interactive Lock-Screen Alarms**: Configurable class reminders (5 to 30 mins before) that trigger a full-screen alarm. Users can mark attendance (`Attended`, `Missed`, `Cancelled`) with a single tap directly from the alarm screen.
- **Cloud Sync & History Log**: Full history of attendance records is safely stored in the backend database. Users can easily view, edit, or delete past logs if they made a mistake marking attendance.

### 🎨 7. Dynamic App Customization & Staff Control

- **Backend-Driven Campaigns**: Supports live administrative theme hex color overrides, dynamic top banners, and one-time Lottie pop-up announcements on app launch.
- **Staff Portals**: Dedicated moderation dashboards for Community Heads and Global Admins to manage members, assign Hub Admins, suspend or permanently delete entire campus instances, set storage quotas, auto-assign roll numbers, and broadcast campus-wide push notifications.

## 🛠️ Tech Stack & Dependencies

- **Framework**: Flutter (Dart)
- **State Management**: Provider (`ChangeNotifier`, `ChangeNotifierProxyProvider`)
- **Real-time Networking**: `web_socket_channel`, `http`
- **Push & Local Notifications**: `firebase_messaging`, `firebase_core`, `flutter_local_notifications`
- **Media & File Handling**: `cached_network_image`, `file_picker`, `url_launcher`, `lottie`
- **Secure Storage**: `flutter_secure_storage`, `shared_preferences`

## 🏗️ System Architecture & App Data Flow

Campus Square follows a **Feature-First Layered Architecture** with strict separation of concerns across state management, API networking, and local persistence.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          1. PRESENTATION LAYER (UI)                         │
│   (Screens, Widgets, BottomSheets, Modals, Forms, Navigation/Routing)       │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ Listens / Dispatches Actions
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                        2. STATE MANAGEMENT LAYER                            │
│                             (Provider Package)                              │
│                                                                             │
│  ├─ CampusSquareAuth (User Session, JWTs, RBAC)                             │
│  ├─ ThemeProvider (Dynamic Colors, Dark/Light Mode)                         │
│  └─ NotificationProvider (FCM Streams, Local History, Unread Badges)        │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ Calls Services
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                        3. DATA & NETWORKING LAYER                           │
│                                                                             │
│  ├─ ApiClient (REST requests, Token Injection, 401 Retries)                 │
│  ├─ WebSocketChannel (Real-time Chat, Typing Indicators, Presence)          │
│  └─ Firebase Cloud Messaging (Background Push Notifications)                │
└───────────┬─────────────────────────────────────────────────────┬───────────┘
            │ Caches Data                                         │ Fetches
┌───────────▼──────────────────────────┐             ┌────────────▼───────────┐
│     4. LOCAL PERSISTENCE LAYER       │             │   FASTAPI BACKEND      │
│                                      │             │                        │
│  ├─ SecureStorage (JWTs, Profile)    │ ◄─────────► │  ├─ PostgreSQL         │
│  ├─ SharedPreferences (REST Cache)   │             │  ├─ Supabase (Files)   │
│  └─ SQLite / Local DB (Alarms)       │             │  └─ WebSockets Hub     │
└──────────────────────────────────────┘             └────────────────────────┘
```

## ⚙️ Core Layers Explained

1. **Presentation Layer** (`lib/features/`)

Each major feature of the app (Square, Bazaar, Vault, Hubs, Chat, Timetable) is isolated in its own folder. The UI relies on `context.watch<T>()` to rebuild reactively when the underlying state changes. Navigation is handled natively, with distinct entry points (`main_student.dart` and `main_staff.dart`) utilizing dedicated routing guards (`StudentRouteGuard` and `StaffRouteGuard`) to gatekeep unauthenticated or unauthorized access based on user roles.

2. **State Management** (`ChangeNotifier` + `Provider`)

Global app state is managed using the `provider` package at the root of the app.

- **CampusSquareAuth**: Acts as the source of truth for the user's identity. It loads the cached profile on startup and handles JWT lifecycle (login, logout, forced password changes).
- **ThemeProvider**: Listens for dynamic hex codes from the backend (`/api/utils/app-campaign`) and instantly repaints the `MaterialApp` theme.
- **NotificationProvider**: A `ChangeNotifierProxyProvider` that depends on `CampusSquareAuth`. It listens to Firebase streams and maintains the in-app notification center history.

3. **Data & Networking** (`ApiClient`)

The `ApiClient` is a custom wrapper around the Dart `http` package. It provides centralized logic for:

- **Token Injection**: Automatically attaches `Bearer <token>` to every request.
- **Token Rotation**: Intercepts `401 Unauthorized` responses, uses the Refresh Token to get a new Access Token, and retries the failed request seamlessly.
- **Offline-First Fallback**: Intercepts `SocketException` (no internet). If the request is a `GET`, it searches `SharedPreferences` for a cached JSON string and returns it with a `200 OK`, triggering an `isOfflineNotifier` to show an "Offline Mode" banner in the UI.

4. **Local Persistence** (`SecureStorageService`)

- **flutter_secure_storage**: Used for highly sensitive data (JWTs, User Profile, Chat Drafts, Failed Messages queue).
- **shared_preferences**: Used for non-sensitive, high-volume data (API GET response caching, UI themes, FCM topic toggles, offline timetable arrays).

## 🔄 Data Flow Lifecycles

1. **The Offline-First REST Lifecycle**

- When a user opens the "Square Feed" without an internet connection:

- UI calls `ApiClient.authenticatedRequest(..., "/api/square/notices", method: "GET")`.

- `http.get` throws a `SocketException`.

- `ApiClient` catches the exception, checks `SharedPreferences` for `CACHE_/api/square/notices`.

- `ApiClient` sets `isOfflineNotifier.value = true` and returns the cached JSON.

- The UI renders the cached feed and displays a red "Offline" icon in the AppBar.

2. **Real-Time Chat & WebSocket Lifecycle**

When a user enters a Direct Message or Team Chat (`ChatScreen`):

- **Init**: The app fetches message history via REST (`GET /api/chat/.../messages`).

- **Connect**: A secure WebSocket connects to `wss://.../api/chat/ws/{id}?token=JWT`.

- **Listen**: The app listens to the `_channel!.stream`. If a `new_message` payload arrives, it is parsed and inserted at index `0` of the local `_messages` list. `setState()` is called to animate the bubble into view.

- **Send**: User types a message. The app instantly adds a "fake" message bubble to the UI with a `sending` status clock icon and pushes the JSON payload to the WebSocket sink. Once the backend broadcasts it back, the `sending` icon changes to a `delivered` checkmark.

3. **Dynamic Campaign & Theming Lifecycle**

- App launches and hits `Dashboard`.

- `_checkAppCampaign()` fires a GET to `/api/utils/app-campaign`.

- If the backend returns `primary_color_hex: "#10B981"`, the dashboard calls `context.read<ThemeProvider>().updatePrimaryColor()`.

- `ThemeProvider` parses the Hex, sets it as the new Material Seed Color, saves it to `SharedPreferences`, and calls `notifyListeners()`.

- The entire application repaints instantly to the new color scheme.

## 📂 Detailed Folder Structure

```
lib/
├── core/
│   ├── network/
│   │   └── api_client.dart            # HTTP wrapper, interceptors, offline cache
│   ├── services/
│   │   ├── local_notification_service # Lock-screen alarms & class reminders
│   │   ├── notification_service       # FCM Background handler & NotificationProvider
│   │   └── secure_storage_service     # Encrypted local storage handlers
│   └── theme/
│       ├── app_theme.dart             # Material 3 ThemeData generation
│       └── theme_provider.dart        # Dynamic color state management
│
├── features/
│   ├── admin/                         # Global Admin Dashboards & Broadcasts
│   ├── auth/                          # Login, Register, OTP, AuthProvider
│   ├── bazaar/                        # Marketplace listing, buying, and selling
│   ├── chat/                          # WebSocket Chat UI, Media Viewers, Messaging Hub
│   ├── community/                     # Community Head specific moderation tools
│   ├── dashboard/                     # Root navigation & Dynamic Banners
│   ├── hubs/                          # Club Dashboards, Study Groups, Team Management
│   ├── profile/                       # User settings, Karma UI, Quotas
│   ├── square/                        # Community Feed, Voting, Nested Comments
│   ├── timetable/                     # Cloud Schedule & Attendance tracking
│   └── vault/                         # Department-wise academic file storage
│
├── firebase_options.dart              # Auto-generated FlutterFire config
├── main_student.dart                  # Application Entrypoint for Students
└── main_staff.dart                    # Application Entrypoint for Staff/Admins
```

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (3.x or higher)
- Android Studio
- A running instance of the [Campus Square Backend](https://github.com/dilawarzAlgorithm/campus-square-backend)

### Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/dilawarzAlgorithm/campus-square.git
   cd campus-square
   ```

2. Install dependencies

   ```bash
   flutter pub get
   ```

3. Configure Environment Variables
   Create a .env file in the root directory:

   ```bash
   API_BASE_URL=http://YOUR_BACKEND_IP:8000
   ```

4. Firebase Setup
   - Place google-services.json inside android/app/.
   - Configure Firebase for iOS using Xcode or run flutterfire configure.

5. Run the application

- To run the Student app:
  ```bash
  flutter build apk -t lib/main_student.dart --no-tree-shake-icons
  ```
- To run the Staff & Admin portal:
  ```bash
  flutter build apk -t lib/main_staff.dart --no-tree-shake-icons
  ```

> Developed for the Campus Square Ecosystem.
