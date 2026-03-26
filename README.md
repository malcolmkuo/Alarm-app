# Alarm App

iOS 26 proof-of-concept: Person A sends a signal, Person B's iPhone fires a native AlarmKit alarm — bypassing silent mode with a Lock Screen / Dynamic Island UI.

---

## How It Works

```
Person A (app open)        Relay Server            Person B
        │                       │                       │
        ├── trigger_alarm ──────>│                       │
        │                       ├── alarm_ringing ──────>│  (app open → WebSocket)
        │                       │                       │
        │                       ├── APNs silent push ───>│  (app closed → wakes app)
        │                       │                       │
        │                       │               AlarmKit fires full alarm UI
```

**App open**: server relays `alarm_ringing` over WebSocket → countdown → AlarmKit fires.
**App closed**: server sends a silent APNs push → iOS wakes the app in the background → `AppDelegate` fires AlarmKit.

---

## Requirements

- Xcode 26 beta or later
- iOS 26 device or simulator
- Node.js (for the relay server)
- **Apple Developer Program membership** ($99/yr) — required for AlarmKit and APNs on a real device

---

## Xcode Setup (first time only)

1. Open `alarm_app.xcodeproj`
2. Select the `alarm_app` target → **Signing & Capabilities**
3. Set **Team** to your Apple Developer account
4. Click **+ Capability** and add:
   - **Alarms**
   - **Background Modes** → check **Remote notifications**
5. Under the **Info** tab, confirm these keys exist (they should already be there):
   - `NSAlarmKitUsageDescription`
   - `NSMicrophoneUsageDescription`
   - `UIBackgroundModes` → `remote-notification`

---

## Running the App

### 1. Start the relay server

```bash
cd alarm-server
npm install
node server.js
```

The server runs on `ws://localhost:8080` by default.

### 2. Build and run the app (⌘R)

- Grant **Alarms** permission when prompted
- In the app, enter `ws://localhost:8080` (or the Render URL if using the deployed server) and tap **Connect**

### 3. Send a test alarm

On the connected device/simulator, tap **Send Alarm**. The other connected device will show a countdown and fire the alarm.

---

## Testing APNs (alarm when app is closed)

There are two ways depending on whether you're on a simulator or real device.

---

### Option A — Simulator (no Apple account needed)

The simulator bypasses Apple's servers entirely. You can inject a push directly from the terminal.

1. Build and run the app on the simulator
2. Fully close the app (Cmd+Shift+H twice, then swipe it up)
3. Run:

```bash
xcrun simctl push booted com.test.alarm-app alarm_app/test-push.apns
```

The alarm should fire within a second.

---

### Option B — Real Device (Apple Developer account required)

#### Step 1 — Register the Bundle ID

1. Go to **developer.apple.com → Certificates, IDs & Profiles → Identifiers**
2. Click **+** → **App IDs** → **App**
3. Enter Bundle ID: `com.test.alarm-app`
4. Under Capabilities, check **Push Notifications** → **Save**

#### Step 2 — Create an APNs Auth Key

1. Go to **developer.apple.com → Keys**
2. Click **+** → give it any name → check **Apple Push Notifications service (APNs)** → **Continue** → **Register**
3. **Download** the `.p8` file — it can only be downloaded once
4. Note down:
   - **Key ID** — shown on the key detail page (10 chars, e.g. `AB12CD34EF`)
   - **Team ID** — shown in the top-right of the developer portal under your name (10 chars)

#### Step 3 — Get Your Device Token

1. Connect your iPhone and select it as the Xcode run target
2. Build and run the app (⌘R)
3. Look at the Xcode console — it will print:
   ```
   📱 Device token: a1b2c3d4e5f6...
   ```
   Copy the full 64-character hex string.

#### Step 4 — Fill in the Test Script

Open `alarm-server/test-apns.js` and fill in the four constants at the top:

```js
const KEY_PATH     = "./AuthKey_XXXXXXXXXX.p8"; // path to your downloaded .p8 file
const KEY_ID       = "XXXXXXXXXX";              // from Step 2
const TEAM_ID      = "XXXXXXXXXX";              // from Step 2
const DEVICE_TOKEN = "PASTE_TOKEN_HERE";        // from Step 3
```

#### Step 5 — Send the Push

1. **Fully close the app on your device** — swipe it up in the app switcher so it is completely killed
2. Run:

```bash
cd alarm-server
node test-apns.js
```

3. The alarm should fire on your device within a few seconds

#### Troubleshooting

| Error | Fix |
|---|---|
| `InvalidProviderToken` | Wrong Key ID or Team ID — double-check both |
| `BadDeviceToken` | Token is stale — rebuild the app and copy a fresh token from Xcode |
| `TopicDisallowed` | Bundle ID not registered for push in the developer portal (Step 1) |
| `DeviceTokenNotForTopic` | Bundle ID in the script doesn't match the app that was built |
| Push received but no alarm | Go to **Settings → your app → Background App Refresh** and enable it |

---

## Deploying the Server (optional)

The relay server is configured to deploy to [Render.com](https://render.com) free tier.

1. Push this repo to GitHub
2. Create a new **Web Service** on Render, connect the repo, set root directory to `alarm-server`
3. Start command: `node server.js`
4. Once deployed, use the `wss://your-app.onrender.com` URL in the app instead of `localhost`

To enable APNs on the deployed server, add these environment variables in the Render dashboard:

| Variable | Value |
|---|---|
| `APNS_KEY_BASE64` | Contents of your `.p8` file, base64-encoded: `base64 -i AuthKey_XXX.p8` |
| `APNS_KEY_ID` | Your 10-char Key ID |
| `APNS_TEAM_ID` | Your 10-char Team ID |
| `APNS_BUNDLE_ID` | `com.test.alarm-app` |
| `APNS_PRODUCTION` | `false` for development builds, `true` for App Store builds |

---

## File Reference

| File | Purpose |
|---|---|
| `alarm_app/ContentView.swift` | UI, WebSocket client, countdown, AlarmKit trigger |
| `alarm_app/AppDelegate.swift` | APNs token registration + silent push handler |
| `alarm_app/test-push.apns` | Simulator push payload for local testing |
| `alarm-server/server.js` | WebSocket relay + APNs sender |
| `alarm-server/test-apns.js` | Local script to send a push directly to a real device |
| `alarm-app-Info.plist` | App permissions and background mode config |
