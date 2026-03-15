// alarm-server/server.js
// Relay: receives trigger_alarm JSON, broadcasts alarm_ringing to all OTHER clients.
// Run locally: node server.js
// Deploy: push to GitHub, connect to Render.com as a Web Service (free tier)

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 8080;

// HTTP server handles health checks (required by Render) and WebSocket upgrades
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
      } else if (payload.event === "alarm_snoozed") {
        console.log(`😴 Relaying alarm_snoozed to ${wss.clients.size - 1} other client(s)`);
        relay(JSON.stringify({ event: "alarm_snoozed" }));
      }
    } catch {
      console.warn("⚠️  Non-JSON message ignored:", text);
    }
  });

  ws.on("close", () =>
    console.log(`🔌 Client disconnected (total: ${wss.clients.size})`)
  );
  ws.on("error", (err) => console.error("❌ Client error:", err.message));
});
