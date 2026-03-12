# Alarm-app

iOS 26 proof-of-concept: Person A sends a signal, Person B's iPhone fires a native AlarmKit alarm — bypassing silent mode with Lock Screen / Dynamic Island UI.

## How it works

```
Mac terminal          WebSocket server        iPhone
trigger.js  ───────▶  server.js  ───────────▶  ContentView  (app open)
                         │
                         └── APNs ───────────▶  AppDelegate  (app closed)
```

When the app is **open**: WebSocket delivers `alarm_ringing` → countdown UI → AlarmKit fires.
When the app is **closed**: server sends a silent APNs push → AppDelegate wakes the app → AlarmKit fires.

## Requirements

- Xcode 26+ with iOS 26 simulator or real iPhone
- Node.js
- Paid Apple Developer account (required for AlarmKit entitlement)

## Xcode setup

1. Target → Signing & Capabilities → add **Alarms** capability
2. Target → Signing & Capabilities → add **Background Modes** → check **Remote notifications**
3. Target → Info → add key: `NSAlarmKitUsageDescription`

## Run

**1. Start the server**
```bash
cd alarm-server && node server.js
```

**2. Run the app** (⌘R), tap **Connect**

**3. Trigger from your Mac**
```bash
node trigger.js        # 5 second countdown (default)
node trigger.js 3      # 3 second countdown
```

## Background (app closed) setup

For alarms to fire when the app is closed, the server needs to send a silent APNs push.
This requires three things from your Apple Developer account:

1. **Device token** — printed to Xcode console on first launch: `📱 Device token: abc123...`
2. **APNs Auth Key** — generate at developer.apple.com → Certificates → Keys
3. **Server APNs integration** — server sends a silent push using the token + key

Silent push payload format:
```json
{
  "aps": { "content-available": 1 },
  "event": "alarm_ringing",
  "countdown": 5
}
```

## Files

| File | Purpose |
|---|---|
| `alarm_app/ContentView.swift` | UI + WebSocket listener + countdown + AlarmKit |
| `alarm_app/AppDelegate.swift` | Silent push handler for background alarm |
| `alarm-server/server.js` | WebSocket relay server |
| `trigger.js` | Mac-side trigger (Person A stand-in) |
