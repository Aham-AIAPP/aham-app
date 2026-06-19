import Foundation
import Speech
import AVFoundation

enum SpeechRecognitionError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case audioEngineError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:          return "未授予语音识别或麦克风权限，请在「系统设置 → 隐私与安全性」中授权"
        case .recognizerUnavailable:  return "语音识别服务不可用，请检查网络连接"
        case .audioEngineError(let e): return "音频引擎错误：\(e.localizedDescription)"
        }
    }
}

/// Apple 原生语音识别服务 — 使用 SFSpeechRecognizer 实现实时中文转写
/// 无需外部服务器，直接对接苹果生态，供调研模块录音自动填写答案
@Observable
@MainActor
final class SpeechRecognitionService {

    // MARK: - Public State

    private(set) var isRecording = false
    private(set) var pendingText = ""           // partial 实时预览（不触发填入）
    private(set) var latestConfirmedText = ""   // final 片段（触发调研自动填入）
    private(set) var recordingDuration: TimeInterval = 0
    private(set) var micPermissionGranted = false
    private(set) var speechPermissionGranted = false
    private(set) var lastError: String?

    var formattedDuration: String {
        let total = Int(recordingDuration)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Private

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var durationTimer: Timer?
    private var renewTimer: Timer?
    private var segmentDebounceTimer: Timer?
    private var sessionStart: Date?
    private var lastConfirmedText = ""

    /// Apple Speech 单次请求约 1 分钟，55s 后自动续接
    private static let renewInterval: TimeInterval = 55
    /// partial 结果稳定多久后视为"已确认片段"，驱动自动填入（中文句间停顿约 0.8s，1.0s 平衡响应与准确性）
    private static let segmentDebounceInterval: TimeInterval = 1.0

    // MARK: - Permissions

    func checkPermissions() async {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .authorized {
            micPermissionGranted = true
        } else {
            micPermissionGranted = await AVCaptureDevice.requestAccess(for: .audio)
        }

        speechPermissionGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Recording Control

    func startRecording() throws {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }
        guard micPermissionGranted && speechPermissionGranted else {
            throw SpeechRecognitionError.notAuthorized
        }

        lastError = nil
        pendingText = ""
        latestConfirmedText = ""
        lastConfirmedText = ""

        try startSession()

        isRecording = true
        sessionStart = Date()
        recordingDuration = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.sessionStart else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
        scheduleRenew()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        cancelTimers()
        stopSession()
        pendingText = ""
    }

    // MARK: - Private Session

    private func startSession() throws {
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13, *) {
            request.addsPunctuation = true
        }

        guard let recognizer else { return }
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.handleResult(result, error: error)
            }
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            task.cancel()
            throw SpeechRecognitionError.audioEngineError(error)
        }

        audioEngine = engine
        recognitionRequest = request
        recognitionTask = task
    }

    private func stopSession() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func handleResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let error {
            // isRecording 已为 false 说明是主动调 stopRecording() 触发的取消，直接忽略
            guard isRecording else { return }
            let code = (error as NSError).code
            // 216 = cancelled（主动停止）, 1110 = session ended（正常结束）
            if code != 216 && code != 1110 {
                lastError = error.localizedDescription
            }
            return
        }
        guard let result else { return }

        let text = result.bestTranscription.formattedString

        if result.isFinal {
            // 真正的 final（通常在 endAudio 后）
            segmentDebounceTimer?.invalidate()
            segmentDebounceTimer = nil
            if !text.isEmpty && text != lastConfirmedText {
                lastConfirmedText = text
                latestConfirmedText = text
            }
            pendingText = ""
        } else {
            // partial 结果：更新实时预览，并启动 1.5s 防抖定时器
            // Apple Speech 录音过程中只给 partial，稳定 1.5s 后视为一个完整片段推送给 AI
            pendingText = text
            segmentDebounceTimer?.invalidate()
            guard !text.isEmpty else { return }
            segmentDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: Self.segmentDebounceInterval, repeats: false
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    let snapshot = self.pendingText
                    guard !snapshot.isEmpty && snapshot != self.lastConfirmedText else { return }
                    self.lastConfirmedText = snapshot
                    self.latestConfirmedText = snapshot
                }
            }
        }
    }

    private func scheduleRenew() {
        renewTimer = Timer.scheduledTimer(withTimeInterval: Self.renewInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.renewSession() }
        }
    }

    /// 续接识别 session，透明重启规避 Apple Speech 1 分钟上限
    private func renewSession() {
        guard isRecording else { return }
        stopSession()
        pendingText = ""
        do {
            try startSession()
            scheduleRenew()
        } catch {
            lastError = error.localizedDescription
            isRecording = false
            cancelTimers()
        }
    }

    private func cancelTimers() {
        durationTimer?.invalidate(); durationTimer = nil
        renewTimer?.invalidate(); renewTimer = nil
        segmentDebounceTimer?.invalidate(); segmentDebounceTimer = nil
        sessionStart = nil
    }
}
