import AVFoundation
import Speech

/// Listens to the microphone and estimates live speaking pace (words per
/// minute) using on-device speech recognition over a rolling time window.
///
/// Everything here runs locally — `requiresOnDeviceRecognition` is set
/// whenever the platform supports it, and no audio or transcript is ever
/// written to disk or sent anywhere.
final class SpeechRateMonitor {
    /// How much recent speech we average over to compute a "live" rate.
    private let windowSeconds: TimeInterval = 8.0
    /// Ignore readings until we've been listening at least this long, so we
    /// don't flash "too slow" the instant coaching mode turns on.
    private let warmupSeconds: TimeInterval = 3.0
    /// SFSpeechRecognitionTask isn't designed to run forever — recycle it
    /// periodically. The audio engine/tap keep running across the recycle.
    private let taskRecycleInterval: TimeInterval = 50.0

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var calcTimer: Timer?
    private var restartTimer: Timer?
    private var monitorStart: Date?

    // Mutated from the recognizer's callback queue *and* read from the main-
    // thread calc timer, so all access is funneled through this serial queue.
    private let stateQueue = DispatchQueue(label: "com.macblinker.speechmonitor.state")
    private var wordTimestamps: [TimeInterval] = []
    private var lastSegmentCount = 0

    /// Called on the main thread with the current live WPM, or `nil` while
    /// still warming up / no usable signal yet.
    var onRateUpdate: ((Double?) -> Void)?

    private(set) var isRunning = false

    /// Requests speech-recognition authorization, then microphone access.
    /// Completion is always called on the main thread.
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            guard speechStatus == .authorized else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { micGranted in
                DispatchQueue.main.async { completion(micGranted) }
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("MacBlinker: speech recognizer unavailable")
            onRateUpdate?(nil)
            return
        }

        stateQueue.sync {
            wordTimestamps.removeAll()
            lastSegmentCount = 0
        }
        monitorStart = Date()

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("MacBlinker: failed to start audio engine — \(error)")
            inputNode.removeTap(onBus: 0)
            return
        }

        isRunning = true
        beginRecognitionTask()

        calcTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.recomputeRate()
        }
        restartTimer = Timer.scheduledTimer(withTimeInterval: taskRecycleInterval, repeats: true) { [weak self] _ in
            self?.beginRecognitionTask()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        calcTimer?.invalidate(); calcTimer = nil
        restartTimer?.invalidate(); restartTimer = nil

        recognitionTask?.cancel(); recognitionTask = nil
        recognitionRequest?.endAudio(); recognitionRequest = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        stateQueue.sync {
            wordTimestamps.removeAll()
            lastSegmentCount = 0
        }
        monitorStart = nil
    }

    // MARK: - Recognition task lifecycle

    private func beginRecognitionTask() {
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request
        stateQueue.sync { lastSegmentCount = 0 }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            self.ingest(segments: result.bestTranscription.segments)
        }
    }

    /// Speech results resend the whole hypothesis each time, so we only
    /// count segments we haven't already counted. Timestamp is receipt time
    /// (not the in-audio timestamp) — close enough for a rolling rate.
    private func ingest(segments: [SFTranscriptionSegment]) {
        let now = Date().timeIntervalSinceReferenceDate
        stateQueue.async { [weak self] in
            guard let self, segments.count > self.lastSegmentCount else { return }
            let newCount = segments.count - self.lastSegmentCount
            self.wordTimestamps.append(contentsOf: Array(repeating: now, count: newCount))
            self.lastSegmentCount = segments.count
        }
    }

    private func recomputeRate() {
        guard let monitorStart else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let elapsedSinceStart = Date().timeIntervalSince(monitorStart)

        stateQueue.async { [weak self] in
            guard let self else { return }
            self.wordTimestamps.removeAll { now - $0 > self.windowSeconds }
            let count = self.wordTimestamps.count

            DispatchQueue.main.async {
                guard elapsedSinceStart >= self.warmupSeconds else {
                    self.onRateUpdate?(nil)
                    return
                }
                let effectiveWindow = Swift.min(self.windowSeconds, elapsedSinceStart)
                guard effectiveWindow > 0 else {
                    self.onRateUpdate?(nil)
                    return
                }
                let wpm = Double(count) / (effectiveWindow / 60.0)
                self.onRateUpdate?(wpm)
            }
        }
    }
}
