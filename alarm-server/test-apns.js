// alarm-server/test-apns.js
// Local APNs test — sends a silent push directly to a real device.
// Usage: node test-apns.js
//
// Fill in the four constants below before running.

const apn = require("@parse/node-apn");

// ---- FILL THESE IN --------------------------------------------------------
const KEY_PATH  = "./AuthKey_XXXXXXXXXX.p8"; // path to your downloaded .p8 file
const KEY_ID    = "XXXXXXXXXX";              // 10-char Key ID from developer.apple.com
const TEAM_ID   = "XXXXXXXXXX";              // 10-char Team ID (top-right of dev portal)
const DEVICE_TOKEN = "PASTE_DEVICE_TOKEN_HERE"; // from Xcode console: "📱 Device token: ..."
// ---------------------------------------------------------------------------

const BUNDLE_ID = "com.test.alarm-app";      // must match Xcode project

const provider = new apn.Provider({
  token: { key: KEY_PATH, keyId: KEY_ID, teamId: TEAM_ID },
  production: false, // false = sandbox (development builds); true = App Store builds
});

const note = new apn.Notification();
note.contentAvailable = 1;
note.pushType = "background";
note.priority = 5;               // required for background pushes (5 = normal, 10 = high)
note.payload = { event: "alarm_ringing", countdown: 5 };
note.topic = BUNDLE_ID;

console.log(`Sending APNs push to ...${DEVICE_TOKEN.slice(-8)}`);

provider.send(note, DEVICE_TOKEN).then((result) => {
  if (result.sent.length > 0) {
    console.log("✅ Push sent successfully");
  }
  if (result.failed.length > 0) {
    console.error("❌ Push failed:", JSON.stringify(result.failed, null, 2));
  }
  provider.shutdown();
});
