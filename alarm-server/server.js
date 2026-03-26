// alarm-server/server.js
// Relay: receives trigger_alarm JSON, broadcasts alarm_ringing to all OTHER clients.
// Also stores APNs device tokens and sends silent pushes when the recipient app is closed.
// Run locally: node server.js
// Deploy: push to GitHub, connect to Render.com as a Web Service (free tier)

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 8080;

// --- APNs setup -----------------------------------------------------------
// Required env vars: APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID
// Key material (one of): APNS_KEY_BASE64 (base64 of .p8 file) or APNS_KEY_PATH
// Optional: APNS_PRODUCTION=true  (defaults to sandbox)

let apn = null;
let apnsProvider = null;

try {
  apn = require("@parse/node-apn");
} catch {
  console.log("ℹ️  @parse/node-apn not installed — APNs disabled");
}

if (apn && process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID && process.env.APNS_BUNDLE_ID) {
  const keyConfig = process.env.APNS_KEY_BASE64
    ? { key: Buffer.from(process.env.APNS_KEY_BASE64, "base64").toString() }
    : process.env.APNS_KEY_PATH
    ? { key: process.env.APNS_KEY_PATH }
    : null;

  if (keyConfig) {
    apnsProvider = new apn.Provider({
      token: { ...keyConfig, keyId: process.env.APNS_KEY_ID, teamId: process.env.APNS_TEAM_ID },
      production: process.env.APNS_PRODUCTION === "true",
    });
    console.log(`🍎 APNs provider initialized (production: ${process.env.APNS_PRODUCTION === "true"})`);
  } else {
    console.log("ℹ️  APNs: APNS_KEY_BASE64 or APNS_KEY_PATH required — APNs disabled");
  }
} else if (apn) {
  console.log("ℹ️  APNs not configured (set APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID to enable)");
}

function sendApnsPush(deviceToken, countdown) {
  if (!apnsProvider) return;
  const note = new apn.Notification();
  note.contentAvailable = 1;
  note.payload = { event: "alarm_ringing", countdown };
  note.topic = process.env.APNS_BUNDLE_ID;
  apnsProvider.send(note, deviceToken).then((result) => {
    if (result.failed.length > 0) {
      console.warn("⚠️  APNs failed:", JSON.stringify(result.failed));
    } else {
      console.log(`✅ APNs push sent to ...${deviceToken.slice(-8)}`);
    }
  });
}

// Maps deviceToken → WebSocket (or null if that token's ws disconnected).
// Re-populated whenever users open the app and connect.
const tokenRegistry = new Map();

// --------------------------------------------------------------------------

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("Alarm relay server running");
});

const wss = new WebSocketServer({ server });

server.listen(PORT, () => {
  console.log(`✅ Alarm relay listening on port ${PORT}`);

  // Keep Render free tier alive — ping ourselves every 14 minutes
  const selfURL = process.env.RENDER_EXTERNAL_URL;
  if (selfURL) {
    setInterval(() => {
      http.get(selfURL, (r) => r.resume()).on("error", () => {});
    }, 14 * 60 * 1000);
    console.log(`♻️  Keep-alive enabled → ${selfURL}`);
  }
});

wss.on("connection", (ws) => {
  console.log(`🔌 Client connected (total: ${wss.clients.size})`);

  ws.on("message", (data) => {
    const text = data.toString();
    console.log(`📥 Received: ${text}`);

    try {
      const payload = JSON.parse(text);

      const relay = (msg) => {
        wss.clients.forEach((client) => {
          if (client !== ws && client.readyState === 1) client.send(msg);
        });
      };

      if (payload.event === "trigger_alarm") {
        const countdown = payload.countdown ?? 5;
        const response = JSON.stringify({
          event: "alarm_ringing",
          countdown,
          ...(payload.voiceData && { voiceData: payload.voiceData }),
        });
        console.log(`🚨 Broadcasting alarm_ringing (${countdown}s, voice: ${!!payload.voiceData}) to ${wss.clients.size - 1} other client(s)`);
        relay(response);

        // APNs: push to registered tokens whose WebSocket is no longer open
        let apnsSent = 0;
        for (const [token, tokenWs] of tokenRegistry) {
          if (!tokenWs || tokenWs.readyState !== 1) {
            sendApnsPush(token, countdown);
            apnsSent++;
          }
        }
        if (apnsSent > 0) {
          console.log(`🍎 APNs push queued for ${apnsSent} disconnected client(s)`);
        }
      } else if (payload.event === "register_token") {
        if (payload.deviceToken) {
          tokenRegistry.set(payload.deviceToken, ws);
          console.log(`📱 Token registered: ...${payload.deviceToken.slice(-8)} (registry size: ${tokenRegistry.size})`);
        }
      } else if (payload.event === "alarm_snoozed") {
        console.log(`😴 Relaying alarm_snoozed to ${wss.clients.size - 1} other client(s)`);
        relay(JSON.stringify({ event: "alarm_snoozed" }));
      }
    } catch {
      console.warn("⚠️  Non-JSON message ignored:", text);
    }
  });

  ws.on("close", () => {
    console.log(`🔌 Client disconnected (total: ${wss.clients.size})`);
    // Mark this ws as disconnected in the registry (token stays — re-registered on next app open)
    for (const [token, tokenWs] of tokenRegistry) {
      if (tokenWs === ws) tokenRegistry.set(token, null);
    }
  });

  ws.on("error", (err) => console.error("❌ Client error:", err.message));
});
