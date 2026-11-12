import Foundation
import Speech
@preconcurrency import AVFoundation
import Combine

@MainActor
final class VoiceInput: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published var transcript = ""
    @Published var message: String?
    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var token: UUID?
    private var hasTap = false
    private var finishTask: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?
    private var isFinishing = false
    private var audioActive = false
    private var activationInFlight = false
    private let audioQueue = DispatchQueue(label: "MemoBooks.audioSession", qos: .userInitiated)

    func start() async {
        guard token == nil else { return }
        guard !activationInFlight else { message = "마이크를 정리하고 있어요. 잠시 후 다시 눌러 주세요"; return }
        let id = UUID()
        token = id
        isStarting = true
        message = nil
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard token == id else { return }
        guard permission == .authorized else { fail("설정에서 음성 인식 권한을 허용해 주세요"); return }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard token == id else { return }
        guard microphone else { fail("설정에서 마이크 권한을 허용해 주세요"); return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            fail("한국어 기기 내 음성인식을 사용할 수 없어요. 키보드로 입력해 주세요")
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            activationInFlight = true
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                audioQueue.async {
                    do {
                        try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
                        try audio.setActive(true)
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
            activationInFlight = false
            audioActive = true
            guard token == id else { stop(); return }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            transcript = ""
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                fail("마이크를 사용할 수 없어요"); return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            hasTap = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                let failed = error != nil
                Task { @MainActor in
                    guard let self, self.token == id else { return }
                    if let text { self.transcript = text }
                    if final || failed {
                        self.stop()
                        if failed { self.message = "음성인식이 종료됐어요. 입력된 내용을 확인해 주세요" }
                    }
                }
            }
            engine.prepare()
            try engine.start()
            isStarting = false
            isRecording = true
            limitTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(55))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        } catch { activationInFlight = false; fail("마이크를 시작하지 못했어요. 다른 녹음 앱을 종료하고 다시 시도해 주세요") }
    }

    // Let the recognizer return its final words instead of immediately cancelling.
    func finish() {
        guard isRecording else { stop(); return }
        guard !isFinishing else { return }
        isFinishing = true
        message = "마지막 말을 정리하고 있어요"
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        finishTask?.cancel(); finishTask = nil
        limitTask?.cancel(); limitTask = nil
        isFinishing = false
        token = nil
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        isStarting = false
        if message == "마지막 말을 정리하고 있어요" { message = nil }
        if audioActive {
            audioActive = false
            audioQueue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    private func fail(_ text: String) { stop(); message = text }
}
