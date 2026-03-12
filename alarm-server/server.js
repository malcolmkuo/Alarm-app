// alarm-server/server.js
// Relay: receives trigger_alarm JSON, broadcasts alarm_ringing to all clients.
// Run: node server.js

const { WebSocketServer } = require("ws");

const PORT = 8080;
const wss = new WebSocketServer({ port: PORT });

console.log(`✅ WebSocket server listening on ws://localhost:${PORT}`);

wss.on("connection", (ws) => {
  console.log("🔌 Client connected");

  ws.on("message", (data) => {
    const text = data.toString();
    console.log(`📥 Received: ${text}`);

    try {
      const payload = JSON.parse(text);

      if (payload.event === "trigger_alarm") {
        const countdown = payload.countdown ?? 5;
        const response = JSON.stringify({ event: "alarm_ringing", countdown });
        console.log(`🚨 Broadcasting alarm_ringing with ${countdown}s countdown...`);
        wss.clients.forEach((client) => {
          if (client.readyState === 1) client.send(response);
        });
      }
    } catch {
      console.warn("⚠️  Received non-JSON message, ignoring:", text);
    }
  });

  ws.on("close", () => console.log("🔌 Client disconnected"));
  ws.on("error", (err) => console.error("❌ Client error:", err.message));
});
