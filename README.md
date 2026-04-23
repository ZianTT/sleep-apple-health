# sleep-apple-health

A Swift iOS application that reads sleep data from **Apple Health** (including data recorded by Apple Watch) and syncs your current sleep state to a self-hosted [sleep-status](https://github.com/shenghuo2/sleep-status) backend.

---

## Features

- 📱 **iPhone-only** — Apple Watch data is automatically synced to Apple Health; no separate WatchOS app needed.
- 🌙 **Real-time sleep detection** — Uses `HKObserverQuery` with background delivery so the app reacts the moment HealthKit receives new sleep data.
- ☁️ **Automatic backend sync** — Calls the `/change` endpoint of your sleep-status server whenever the detected sleep state changes.
- ⏱ **Periodic background refresh** — Scheduled `BGAppRefreshTask` runs every ~15 minutes as a fallback.
- ⚙️ **Settings UI** — Configure backend URL and API key, and test the connection right in the app.
- 📊 **Recent sleep records** — Shows the last 10 sleep segments (stage, time range, duration).

---

## Requirements

| Component | Minimum version |
|-----------|----------------|
| iOS       | 16.0           |
| Xcode     | 15.0           |
| Swift     | 5.9            |
| Backend   | [shenghuo2/sleep-status](https://github.com/shenghuo2/sleep-status) |

> An Apple Developer account is required to build and run on a physical device (HealthKit is not available in the simulator).

---

## Getting started

### 1. Clone this repository

```bash
git clone https://github.com/ZianTT/sleep-apple-health.git
cd sleep-apple-health/SleepAppleHealth
```

### 2. Open in Xcode

```bash
open SleepAppleHealth.xcodeproj
```

### 3. Configure signing

1. Select the **SleepAppleHealth** target.
2. Open the **Signing & Capabilities** tab.
3. Choose your development team.
4. Xcode will automatically manage provisioning profiles.

### 4. Enable capabilities (if not already active)

In **Signing & Capabilities**, verify these are present:
- **HealthKit** — with *Background Delivery* checked
- **Background Modes** — *Background fetch* and *Background processing* checked

These are already declared in `SleepAppleHealth.entitlements` and `Info.plist`.

### 5. Build & run

Connect a physical iPhone (HealthKit is not available in the simulator) and press **⌘R**.

---

## Configuration

Open the app and tap the **⚙ gear icon** (top-right) to open Settings:

| Field | Description |
|-------|-------------|
| **Backend URL** | Base URL of your sleep-status server, e.g. `https://your-server:8000` |
| **API Key** | The `key` value from your server's `config.json` |

Tap **Test Connection** to verify the server is reachable, then **Save**.

---

## How it works

```
Apple Watch
    │  (automatic BLE sync)
    ▼
Apple Health (HealthKit)
    │  HKObserverQuery (background delivery)
    ▼
HealthKitManager                    – detects sleep state from samples
    │  onSleepStateChanged callback
    ▼
BackendSyncManager                  – GET /change?key=…&status=1|0
    ▼
sleep-status backend
```

### Sleep state detection logic

1. **Active window** — if any *asleep* sample's time window contains the current time → sleeping.
2. **Recent end** — if the most recent asleep sample ended within the last 15 minutes → sleeping (the Watch may still be writing segments).
3. **Otherwise** → awake.

Asleep stages recognised: `asleepUnspecified`, `asleepCore`, `asleepDeep`, `asleepREM` (iOS 16+).

### Backend API used

| Endpoint | Purpose |
|----------|---------|
| `GET /status` | Fetch current status (used by the connection test) |
| `GET /change?key=KEY&status=1\|0` | Set sleep state (`1` = sleeping, `0` = awake) |

---

## Project structure

```
SleepAppleHealth/
├── SleepAppleHealth.xcodeproj/
│   └── project.pbxproj
└── SleepAppleHealth/
    ├── SleepAppleHealthApp.swift   # App entry point (@main)
    ├── AppDelegate.swift           # HealthKit setup, BGTaskScheduler
    ├── HealthKitManager.swift      # HKObserverQuery, sleep detection
    ├── BackendSyncManager.swift    # HTTP calls to sleep-status backend
    ├── SettingsManager.swift       # UserDefaults persistence
    ├── ContentView.swift           # Main SwiftUI screen
    ├── SettingsView.swift          # Backend configuration screen
    ├── Info.plist                  # HealthKit & background mode permissions
    └── SleepAppleHealth.entitlements
```

---

## Privacy

The app only **reads** sleep data from HealthKit — it never writes back to Apple Health. All communication is between your iPhone and your own self-hosted server; no third-party services are involved.

---

## License

MIT
