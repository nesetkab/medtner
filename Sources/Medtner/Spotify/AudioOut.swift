import AVFoundation
import Foundation

final class AudioOut: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private let slots = DispatchSemaphore(value: 13)
    private let lock = NSLock()
    private let framesPerChunk = 2_048
    private let control = DispatchQueue(label: "medtner.audio.control", qos: .userInteractive)
    private var held = false
    private var gated = false
    private var gateDeadline = Date.distantPast
    private var idleWork: DispatchWorkItem?
    private var generation = 0
    private var lows: (Float, Float, Float) = (0, 0, 0)
    private var peaks: [Float] = [0.02, 0.02, 0.02, 0.02]
    private var userVolume: Float = 0.36
    private var fadeLevel: Float = 1
    private var fadeTimer: DispatchSourceTimer?
    private var activity: NSObjectProtocol?
    private var staging = [Float](repeating: 0, count: 4_096)
    private var stagingFill = 0
    var onLevels: (([Float]) -> Void)?

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.restart()
        }
    }

    func setVolume(_ percent: Int) {
        let linear = Float(min(max(percent, 0), 100)) / 100
        control.async {
            self.userVolume = linear * linear
            self.applyVolume()
        }
    }

    func hold() {
        lock.lock()
        held = true
        lock.unlock()
        fade(to: 0, over: 0.18) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stillHeld = self.held
            self.lock.unlock()
            guard stillHeld else { return }
            self.node.pause()
            self.scheduleIdle()
        }
    }

    func release() {
        lock.lock()
        held = false
        lock.unlock()
        control.async {
            self.fadeTimer?.cancel()
            self.fadeLevel = 0
            self.applyVolume()
        }
        ensureRunning()
        fade(to: 1, over: 0.22, then: nil)
    }

    func interrupt() {
        lock.lock()
        gated = true
        gateDeadline = Date().addingTimeInterval(3)
        lock.unlock()
        fade(to: 0, over: 0.04) { [weak self] in
            guard let self else { return }
            self.node.stop()
            self.fadeLevel = 1
            self.applyVolume()
            self.lock.lock()
            let isHeld = self.held
            self.lock.unlock()
            if !isHeld, self.engine.isRunning { self.node.play() }
        }
    }

    func flush() {
        control.async {
            self.fadeTimer?.cancel()
            self.node.stop()
            self.fadeLevel = 1
            self.applyVolume()
            self.lock.lock()
            let isHeld = self.held
            self.lock.unlock()
            if !isHeld, self.engine.isRunning { self.node.play() }
        }
    }

    func openGate() {
        lock.lock()
        gated = false
        lock.unlock()
    }

    func seeked() {
        lock.lock()
        let wasGated = gated
        gated = false
        lock.unlock()
        if !wasGated { flush() }
    }

    func stream(from handle: FileHandle) {
        lock.lock()
        generation += 1
        let mine = generation
        lock.unlock()
        let thread = Thread { [weak self] in
            self?.read(handle, generation: mine)
        }
        thread.name = "medtner.audio"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func read(_ handle: FileHandle, generation mine: Int) {
        let fd = handle.fileDescriptor
        let bytesPerChunk = framesPerChunk * 4
        var chunk = Data(count: bytesPerChunk)
        while true {
            slots.wait()
            var filled = 0
            var ended = false
            chunk.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                while filled < bytesPerChunk {
                    let n = Darwin.read(fd, base + filled, bytesPerChunk - filled)
                    if n > 0 {
                        filled += n
                    } else if n < 0 && errno == EINTR {
                        continue
                    } else {
                        ended = true
                        break
                    }
                }
            }
            lock.lock()
            let stale = mine != generation
            if gated, Date() > gateDeadline { gated = false }
            let dropping = gated
            lock.unlock()
            let usable = filled - filled % 4
            guard !stale, !dropping, usable > 0, let (buffer, levels) = convert(chunk.prefix(usable)) else {
                slots.signal()
                if ended || stale {
                    try? handle.close()
                    return
                }
                continue
            }
            schedule(buffer, levels: levels)
            if ended {
                try? handle.close()
                return
            }
        }
    }

    func push(_ samples: UnsafePointer<Float>, count: Int) {
        let capacity = framesPerChunk * 2
        var offset = 0
        while offset < count {
            let take = min(capacity - stagingFill, count - offset)
            staging.withUnsafeMutableBufferPointer { destination in
                (destination.baseAddress! + stagingFill).update(from: samples + offset, count: take)
            }
            stagingFill += take
            offset += take
            if stagingFill == capacity {
                emitStaged()
                stagingFill = 0
            }
        }
    }

    private func emitStaged() {
        slots.wait()
        lock.lock()
        if gated, Date() > gateDeadline { gated = false }
        let dropping = gated
        lock.unlock()
        let frames = framesPerChunk
        guard !dropping, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else {
            slots.signal()
            return
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        let left = channels[0], right = channels[1]
        staging.withUnsafeBufferPointer { interleaved in
            for i in 0..<frames {
                left[i] = interleaved[i * 2]
                right[i] = interleaved[i * 2 + 1]
            }
        }
        schedule(buffer, levels: levels(left, right, frames: frames))
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, levels: [Float]) {
        node.scheduleBuffer(buffer, completionCallbackType: .dataRendered) { [weak self] _ in
            self?.slots.signal()
            self?.onLevels?(levels)
        }
        ensureRunning()
    }

    private func convert(_ data: Data) -> (AVAudioPCMBuffer, [Float])? {
        let frames = data.count / 4
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        let left = channels[0], right = channels[1]
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            let scale: Float = 1 / 32_768
            for i in 0..<frames {
                left[i] = Float(Int16(littleEndian: samples[i * 2])) * scale
                right[i] = Float(Int16(littleEndian: samples[i * 2 + 1])) * scale
            }
        }
        return (buffer, levels(left, right, frames: frames))
    }

    private func levels(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) -> [Float] {
        var (low, lowMid, mid) = lows
        var energy: [Float] = [0, 0, 0, 0]
        for i in 0..<frames {
            let m = (left[i] + right[i]) * 0.5
            low += 0.021 * (m - low)
            lowMid += 0.069 * (m - lowMid)
            mid += 0.248 * (m - mid)
            let bands = (low, lowMid - low, mid - lowMid, m - mid)
            energy[0] += bands.0 * bands.0
            energy[1] += bands.1 * bands.1
            energy[2] += bands.2 * bands.2
            energy[3] += bands.3 * bands.3
        }
        lows = (low, lowMid, mid)
        var result: [Float] = [0, 0, 0, 0]
        for band in 0..<4 {
            let rms = (energy[band] / Float(frames)).squareRoot()
            peaks[band] = max(rms, peaks[band] * 0.996, 0.002)
            result[band] = min(rms / peaks[band], 1)
        }
        return result
    }

    private func fade(to target: Float, over seconds: Double, then done: (() -> Void)?) {
        control.async {
            self.fadeTimer?.cancel()
            let start = self.fadeLevel
            let steps = max(Int(seconds / 0.01), 1)
            var step = 0
            let timer = DispatchSource.makeTimerSource(queue: self.control)
            timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                step += 1
                let t = Float(step) / Float(steps)
                let eased = t * t * (3 - 2 * t)
                self.fadeLevel = start + (target - start) * min(eased, 1)
                self.applyVolume()
                if step >= steps {
                    timer.cancel()
                    self.fadeTimer = nil
                    done?()
                }
            }
            self.fadeTimer = timer
            timer.resume()
        }
    }

    private func applyVolume() {
        engine.mainMixerNode.outputVolume = userVolume * fadeLevel
    }

    private func ensureRunning() {
        lock.lock()
        let isHeld = held
        idleWork?.cancel()
        idleWork = nil
        lock.unlock()
        guard !isHeld else { return }
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
            beginActivity()
        }
        if !node.isPlaying { node.play() }
        scheduleIdle()
    }

    private func scheduleIdle() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.node.pause()
            self.engine.pause()
            self.endActivity()
        }
        lock.lock()
        idleWork?.cancel()
        idleWork = work
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func beginActivity() {
        lock.lock()
        defer { lock.unlock() }
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
            reason: "Playing music"
        )
    }

    private func endActivity() {
        lock.lock()
        defer { lock.unlock() }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func restart() {
        engine.stop()
        engine.connect(node, to: engine.mainMixerNode, format: format)
        ensureRunning()
    }
}
