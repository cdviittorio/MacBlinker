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

    /// Called on the main thread with a human-readable problem description
    /// whenever recognition fails, or `nil` once it's healthy again. Lets the
    /// UI surface *why* WPM is stuck at 0 instead of showing a silent blank.
    var onStatus: ((String?) -> Void)?

    private(set) var isRunning = false
    private var consecutiveFailures = 0
    private let maxImmediateFailures = 3

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
            onStatus?("Speech recognizer unavailable for this language/device.")
            return
        }

        stateQueue.sync {
            wordTimestamps.removeAll()
            lastSegmentCount = 0
        }
        monitorStart = Date()
        consecutiveFailures = 0

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
            onStatus?("Couldn't start the audio engine: \(error.localizedDescription)")
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

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.ingest(segments: result.bestTranscription.segments)
            }
            if let error {
                self.handleRecognitionError(error)
            } else if result?.isFinal == true {
                // Recognizer ended the task cleanly (e.g. a silence timeout).
                // Restart promptly so we keep listening instead of going dark
                // until the next scheduled recycle.
                self.scheduleTaskRestart(afterFailure: false)
            }
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
            DispatchQueue.main.async {
                self.consecutiveFailures = 0
                self.onStatus?(nil)
            }
        }
    }

    /// Recognition tasks fail for lots of mundane reasons (silence timeout,
    /// the ~1min task lifetime, transient network hiccups for the
    /// non-on-device path). We log the real error and restart automatically —
    /// but back off if it's failing immediately over and over, which usually
    /// means something structural (e.g. Dictation disabled system-wide, or no
    /// on-device model downloaded for this language) rather than a blip.
    private func handleRecognitionError(_ error: Error) {
        let nsError = error as NSError
        let message = "MacBlinker: speech recognition error — domain=\(nsError.domain) code=\(nsError.code) — \(nsError.localizedDescription)"
        print(message)

        consecutiveFailures += 1
        let hint: String
        if consecutiveFailures > maxImmediateFailures {
            hint = "Mic error (\(nsError.domain) #\(nsError.code)): \(nsError.localizedDescription). " +
                   "Check System Settings → Keyboard → Dictation is ON, and MacBlinker is allowed under Privacy & Security → Microphone/Speech Recognition."
        } else {
            hint = "Mic error (\(nsError.domain) #\(nsError.code)): \(nsError.localizedDescription)"
        }
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(hint)
        }
        scheduleTaskRestart(afterFailure: true)
    }

    private func scheduleTaskRestart(afterFailure: Bool) {
        guard isRunning else { return }
        // Simple back-off: retry quickly at first, slow down if it keeps
        // failing immediately so we don't spin a tight restart loop.
        let delay: TimeInterval = (afterFailure && consecutiveFailures > maxImmediateFailures) ? 5.0 : 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isRunning else { return }
            self.beginRecognitionTask()
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
