# Timer Be Perfect (v3.0.0)

<p align="center">
  <img src="assets/branding/logo-transparent.png" alt="Be Perfect logo" width="160">
</p>

<p align="center">
  <b>A resilient, multi-device synchronized timer and event coordinator for church youth activities.</b>
</p>

<p align="center">
  Developed by <b>Abanoub Samy (<a href="https://github.com/CyberBonk">CyberBonk</a>)</b>.
</p>

---

## 🚀 Overview

**Timer Be Perfect** coordinates live multi-round events across dozens of participant devices with offline survivability, background alarm reliability, and flexible sector-based grouping.

- **Controller**: Creates the room, customizes event sectors, starts rounds, pauses, skips, or adds/removes time on the fly.
- **Participant**: Joins with a 6-digit PIN, enters their name, picks their sector from a live dropdown, and tracks rounds in real time.

---

## ✨ Key Features in v3.0

- 🏢 **Multi-Participant Sectors**:
  - Controllers can create, rename (full Arabic support), and manage sectors live from a dedicated card.
  - Participants select from real-time synchronized sector dropdowns.
  - Dashboards group participants into sector cards with member counts.
- 🔄 **4-State Sync Matrix**:
  - Differentiates between physical internet connectivity and schedule state sync.
  - Clear color badges:
    - 🟢 **Synced + Online**: Live and up to date.
    - 🟠 **Synced + Offline**: Dropped connection, but holds the latest round schedule safely.
    - 🟡 **Out of sync + Online**: Connected but lagging behind room revisions.
    - 🔴 **Out of sync + Offline**: Disconnected and missed a schedule change (requires notice).
- 🔋 **OEM & Background Keepalive**:
  - Persistent Foreground Service and partial WakeLock to keep Android Doze and aggressive battery savers from killing timers and sockets.
- 📢 **Sector-Targeted @Mentions**:
  - Mentioning `@SectorName` alerts and pushes notifications exclusively to all members of that sector.
  - Optional individual `@ParticipantName` targeting.
- ⚙️ **Dynamic Limits in Settings**:
  - User-configurable maximum round duration, cooldown duration (up to 15 min), and step intervals.
- 🌐 **Arabic & English First-Class Support**:
  - Complete bilingual RTL/LTR experience.

---

## 🛠️ Tech Stack & Architecture

- **Frontend**: Flutter 3.x (Dart), Riverpod, Material 3.
- **Backend**: Firebase Cloud Firestore & Realtime Database with dual-path execution (atomic client fallback when Cloud Functions are offline).
- **Notifications**: Local exact alarms + FCM push fan-out.
- **Reliability**: Deterministic offline schedule engine calculating countdowns purely from timestamps without per-second network polling.

---

## 🏃 Quick Start

### Prerequisites
- Flutter SDK `>=3.3.0`
- Android SDK with USB debugging enabled

```bash
# Clone the repository
git clone https://github.com/CyberBonk/Be-Perfect.git
cd Be-Perfect

# Get packages
flutter pub get

# Run tests
flutter test

# Run on connected device
flutter run
```

---

## 📄 License & Credits

Developed with ❤️ by **Abanoub Samy (CyberBonk)** for church youth activities.
