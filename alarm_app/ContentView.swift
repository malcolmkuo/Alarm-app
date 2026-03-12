//  ContentView.swift — alarm_app

import SwiftUI
import AlarmKit

nonisolated struct EmptyMetadata: AlarmMetadata {}

private struct AlarmPayload: Decodable {
    let event: String
    let countdown: Int
}

@MainActor @Observable
final class AlarmViewModel {
    var authState: AlarmManager.AuthorizationState = .notDetermined
    var connected = false
    var lastEvent = "—"
    var countdown: Int? = nil

    private var socket: URLSessionWebSocketTask?
    private let url = URL(string: "ws://localhost:8080")!

    func checkAuth() async {
        guard AlarmManager.shared.authorizationState == .notDetermined else {
            authState = AlarmManager.shared.authorizationState; return
        }
        _ = try? await AlarmManager.shared.requestAuthorization()
        authState = AlarmManager.shared.authorizationState
    }

    func toggleConnection() {
        connected ? disconnect() : connect()
    }

    private func connect() {
        socket = URLSession.shared.webSocketTask(with: url)
        socket?.resume()
        connected = true
        Task { await listen() }
    }

    func disconnect() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil; connected = false
    }

    private func listen() async {
        guard let socket else { return }
        do {
            let msg = try await socket.receive()
            if case .string(let text) = msg, let data = text.data(using: .utf8),
               let payload = try? JSONDecoder().decode(AlarmPayload.self, from: data),
               payload.event == "alarm_ringing" {
                lastEvent = text
                await triggerAlarm(in: payload.countdown)
            }
            await listen()
        } catch {
            connected = false
        }
    }

    private func triggerAlarm(in seconds: Int) async {
        Task { await scheduleAlarm(duration: TimeInterval(seconds)) }
        for i in stride(from: seconds, through: 0, by: -1) {
            withAnimation(.easeInOut(duration: 0.3)) { countdown = i }
            if i > 0 { try? await Task.sleep(for: .seconds(1)) }
        }
        countdown = nil
    }

    private func scheduleAlarm(duration: TimeInterval) async {
        let stop = AlarmButton(text: "Stop", textColor: .red, systemImageName: "stop.circle")
        let attrs = AlarmAttributes<EmptyMetadata>(
            presentation: AlarmPresentation(alert: .init(title: "Alarm!", stopButton: stop)),
            tintColor: .red
        )
        _ = try? await AlarmManager.shared.schedule(id: UUID(), configuration: .timer(duration: duration, attributes: attrs))
    }
}

struct ContentView: View {
    @State private var vm = AlarmViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "alarm.waves.left.and.right").font(.system(size: 64)).foregroundStyle(.red)
            Text("AlarmKit").font(.title2.bold())

            if let count = vm.countdown {
                Text(count == 0 ? "🔔" : "\(count)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(count <= 2 ? .red : .primary)
                    .contentTransition(.numericText(countsDown: true))
                    .frame(height: 120)
            } else {
                VStack(spacing: 6) {
                    badge("AlarmKit", vm.authState == .authorized ? "Authorized" : "Not Authorized",
                          vm.authState == .authorized ? .green : .orange)
                    badge("Socket", vm.connected ? "Connected" : "Disconnected", vm.connected ? .green : .gray)
                    badge("Last event", vm.lastEvent, .secondary)
                }
                .frame(height: 120)
            }

            Divider()

            actionButton(vm.connected ? "Disconnect" : "Connect", vm.connected ? "wifi.slash" : "wifi",
                         vm.connected ? .gray : .blue, vm.toggleConnection)

            if vm.connected {
                Text("node trigger.js")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6)).cornerRadius(8)
                    .padding(.horizontal, 20)
            }
        }
        .padding(40)
        .task { await vm.checkAuth() }
    }

    private func badge(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label): \(value)").font(.subheadline)
        }
    }

    private func actionButton(_ label: String, _ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon).fontWeight(.semibold).foregroundStyle(.white)
                .padding().frame(maxWidth: .infinity)
                .background(color).cornerRadius(12)
        }
        .padding(.horizontal, 20)
    }
}

#Preview { ContentView() }
