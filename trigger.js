// trigger.js — fires alarm on the simulator whether app is open or closed
// Usage:  node trigger.js        (5s default)
//         node trigger.js 3      (custom countdown)

const { execSync } = require("child_process");
const WebSocket = require("./alarm-server/node_modules/ws");
const fs = require("fs");

const countdown = parseInt(process.argv[2]) || 5;
const BUNDLE_ID = "com.test.alarm-app"; // update if your bundle ID changed

// 1. WebSocket → server → app (drives the countdown UI when app is open)
const ws = new WebSocket("ws://localhost:8080");
ws.on("open", () => {
  ws.send(JSON.stringify({ event: "trigger_alarm", countdown }));
  setTimeout(() => ws.close(), 200);
});
ws.on("error", () => {}); // ok if server isn't running

// 2. xcrun simctl push → AppDelegate (schedules the actual AlarmKit alarm)
//    Works whether app is open, backgrounded, or fully closed.
const payload = JSON.stringify({
  "Simulator Target Bundle": BUNDLE_ID,
  aps: { "content-available": 1 },
  event: "alarm_ringing",
  countdown,
});
const tmp = "/tmp/alarm_trigger.apns";
fs.writeFileSync(tmp, payload);
try {
  execSync(`xcrun simctl push booted ${BUNDLE_ID} ${tmp}`, { stdio: "pipe" });
  console.log(`✅ Alarm triggered — ${countdown}s countdown`);
} catch (e) {
  console.error("❌ simctl push failed:", e.stderr?.toString().trim());
  console.error("   Is the simulator running?");
}
