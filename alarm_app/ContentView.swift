//  ContentView.swift — alarm_app

import SwiftUI
import AlarmKit
import AVFoundation
import AudioToolbox

nonisolated struct EmptyMetadata: AlarmMetadata {}

private struct IncomingMessage: Decodable {
    let event: String
    let countdown: Int?
    let voiceData: String?
}

// MARK: - Audio Recorder

@MainActor @Observable
final class AudioRecorder: NSObject {
    var isRecording = false
    var hasRecording = false
    private(set) var recordedData: Data?
    private var recorder: AVAudioRecorder?

    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("voice_alarm.m4a")
    }

    func startRecording() {
        try? AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        recorder = try? AVAudioRecorder(url: fileURL, settings: settings)
        recorder?.record()
        isRecording = true
        hasRecording = false
        recordedData = nil
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        recordedData = try? Data(contentsOf: fileURL)
        hasRecording = recordedData != nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func clear() { recordedData = nil; hasRecording = false }
}

// MARK: - ViewModel

@MainActor @Observable
final class AlarmViewModel {
    var authState: AlarmManager.AuthorizationState = .notDetermined
    var connected = false
    var lastEvent = "—"
    var countdown: Int? = nil
    var alarmFiring = false
    var serverURL: String = ""
    var receivedVoiceData: Data? = nil
    var snoozedBanner = false

    private var socket: URLSessionWebSocketTask?
    private var snoozeTask: Task<Void, Never>?

    init() {
        // When the OS delivers a device token (possibly after the socket is already open),
        // immediately register it with the relay server so it can send APNs for closed-app alarms.
        NotificationCenter.default.addObserver(forName: .deviceTokenReceived, object: nil, queue: .main) { [weak self] notification in
            guard let self, self.connected, let socket = self.socket,
                  let token = notification.object as? String else { return }
            self.sendTokenRegistration(token: token, socket: socket)
        }
    }

    func checkAuth() async {
        guard AlarmManager.shared.authorizationState == .notDetermined else {
            authState = AlarmManager.shared.authorizationState; return
        }
        _ = try? await AlarmManager.shared.requestAuthorization()
        authState = AlarmManager.shared.authorizationState
    }

    func toggleConnection() { connected ? disconnect() : connect() }

    private func connect() {
        guard let url = URL(string: serverURL), url.scheme == "ws" || url.scheme == "wss" else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        connected = true
        // Register APNs token so the server can reach us when the app is closed
        if let token = AppDelegate.deviceToken { sendTokenRegistration(token: token, socket: task) }
        Task { await listen() }
    }

    private func sendTokenRegistration(token: String, socket: URLSessionWebSocketTask) {
        let msg = "{\"event\":\"register_token\",\"deviceToken\":\"\(token)\"}"
        socket.send(.string(msg)) { _ in }
    }

    func disconnect() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil; connected = false
    }

    private func listen() async {
        guard let socket else { return }
        do {
            let msg = try await socket.receive()
            if case .string(let text) = msg,
               let data = text.data(using: .utf8),
               let message = try? JSONDecoder().decode(IncomingMessage.self, from: data) {
                switch message.event {
                case "alarm_ringing":
                    lastEvent = "alarm_ringing"
                    if let b64 = message.voiceData, let audio = Data(base64Encoded: b64) {
                        receivedVoiceData = audio
                    } else {
                        receivedVoiceData = nil
                    }
                    await triggerAlarm(in: message.countdown ?? 5)
                case "alarm_snoozed":
                    lastEvent = "alarm_snoozed"
                    snoozedBanner = true
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        snoozedBanner = false
                    }
                default: break
                }
            }
            await listen()
        } catch { connected = false }
    }

    func sendAlarm(voiceData: Data? = nil) {
        guard connected, let socket else { return }
        var dict: [String: Any] = ["event": "trigger_alarm", "countdown": 5]
        if let voice = voiceData { dict["voiceData"] = voice.base64EncodedString() }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: jsonData, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }

    private func sendSnoozeNotification() {
        guard connected, let socket else { return }
        socket.send(.string("{\"event\":\"alarm_snoozed\"}")) { _ in }
    }

    private func triggerAlarm(in seconds: Int) async {
        guard !alarmFiring, countdown == nil else { return }
        for i in stride(from: seconds, through: 0, by: -1) {
            withAnimation(.easeInOut(duration: 0.3)) { countdown = i }
            if i > 0 { try? await Task.sleep(for: .seconds(1)) }
        }
        countdown = nil
        alarmFiring = true
    }

    func stopAlarm() {
        snoozeTask?.cancel()
        snoozeTask = nil
        alarmFiring = false
        receivedVoiceData = nil
    }

    func snoozeAlarm(minutes: Int = 1) {
        alarmFiring = false
        sendSnoozeNotification()
        // keep receivedVoiceData so voice replays after snooze
        snoozeTask = Task {
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            alarmFiring = true
        }
    }
}

// MARK: - Main View

struct ContentView: View {
    @State private var vm = AlarmViewModel()
    @State private var recorder = AudioRecorder()
    @AppStorage("serverURL") private var savedURL = "wss://your-server.onrender.com"

    var body: some View {
        ZStack(alignment: .top) {
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

                if !vm.connected {
                    TextField("wss://your-server.onrender.com", text: $savedURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.caption, design: .monospaced))
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .padding(.horizontal, 20)
                }

                actionButton(vm.connected ? "Disconnect" : "Connect",
                             vm.connected ? "wifi.slash" : "wifi",
                             vm.connected ? .gray : .blue) {
                    vm.serverURL = savedURL
                    vm.toggleConnection()
                }

                if vm.connected {
                    VoiceRecorderRow(recorder: recorder)

                    Button {
                        vm.sendAlarm(voiceData: recorder.recordedData)
                        recorder.clear()
                    } label: {
                        Label("Send Alarm",
                              systemImage: recorder.hasRecording ? "bell.and.waves.left.and.right.fill" : "bell.fill")
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(40)

            // Snooze-received banner
            if vm.snoozedBanner {
                Text("They snoozed — re-ringing in 1 min")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .clipShape(Capsule())
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4), value: vm.snoozedBanner)
        .task { await vm.checkAuth() }
        .fullScreenCover(isPresented: $vm.alarmFiring) {
            AlarmScreen(onStop: vm.stopAlarm, onSnooze: { vm.snoozeAlarm() }, voiceData: vm.receivedVoiceData)
        }
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

// MARK: - Voice Recorder Row

struct VoiceRecorderRow: View {
    var recorder: AudioRecorder

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    recorder.isRecording ? recorder.stopRecording() : recorder.startRecording()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
                        Text(recorder.isRecording ? "Stop" : "Record Voice").fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(recorder.isRecording ? Color.orange : Color(.systemGray2))
                    .cornerRadius(12)
                }
                if recorder.hasRecording {
                    Button { recorder.clear() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)

            if recorder.isRecording {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Recording…").font(.caption).foregroundStyle(.secondary)
                }
            } else if recorder.hasRecording {
                HStack(spacing: 6) {
                    Image(systemName: "waveform").foregroundStyle(.green)
                    Text("Voice message ready").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Alarm Screen (Apple Clock style)

struct AlarmScreen: View {
    let onStop: () -> Void
    let onSnooze: () -> Void
    let voiceData: Data?

    @State private var audioPlayer: AVAudioPlayer?
    @State private var soundLoop: Task<Void, Never>?

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "h:mm"
        return f.string(from: Date())
    }
    private var amPMString: String {
        let f = DateFormatter(); f.dateFormat = "a"
        f.locale = Locale(identifier: "en_US")
        return f.string(from: Date())
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Top label
                Label(voiceData != nil ? "Voice Alarm" : "Alarm", systemImage: "alarm.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 24)

                // Time display — updates every minute
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(spacing: 0) {
                        Text(timeString)
                            .font(.system(size: 96, weight: .thin, design: .default))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text(amPMString)
                            .font(.system(size: 30, weight: .thin))
                            .foregroundStyle(.white)
                            .padding(.top, 4)
                    }
                }

                Spacer()

                // Snooze button
                Button(action: onSnooze) {
                    Text("Snooze")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

                // Slide to stop
                SlideToStopSlider(onStop: onStop)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 52)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { startSound() }
        .onDisappear { stopSound() }
    }

    private func startSound() {
        if let data = voiceData {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try? AVAudioPlayer(data: data)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
        } else {
            soundLoop = Task {
                while !Task.isCancelled {
                    AudioServicesPlayAlertSound(SystemSoundID(1005))
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    private func stopSound() {
        audioPlayer?.stop(); audioPlayer = nil
        soundLoop?.cancel(); soundLoop = nil
    }
}

// MARK: - Slide to Stop

struct SlideToStopSlider: View {
    let onStop: () -> Void
    @State private var offset: CGFloat = 0

    private let height: CGFloat = 56.0
    private let handleWidth: CGFloat = 52.0

    var body: some View {
        GeometryReader { geo in
            let maxOffset: CGFloat = geo.size.width - handleWidth - 8
            let progress: CGFloat = offset / max(maxOffset, 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: height)

                Text("slide to stop")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(Double(max(0, 1 - progress * 3))))
                    .frame(maxWidth: .infinity)

                RoundedRectangle(cornerRadius: (height - 8) / 2)
                    .fill(.white)
                    .frame(width: handleWidth, height: height - 8)
                    .overlay(
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.black)
                    )
                    .padding(.leading, 4)
                    .offset(x: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                offset = min(max(0, v.translation.width), maxOffset)
                            }
                            .onEnded { _ in
                                if offset > maxOffset * 0.75 {
                                    onStop()
                                } else {
                                    withAnimation(.spring(response: 0.3)) { offset = 0 }
                                }
                            }
                    )
            }
        }
        .frame(height: height)
    }
}

#Preview { ContentView() }
#Preview("Alarm Screen") { AlarmScreen(onStop: {}, onSnooze: {}, voiceData: nil) }
