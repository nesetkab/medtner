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
    private var cutPending = false
    private var discardStaged = false
    private var draining = false
    private var lastRendered: CFAbsoluteTime = 0
    private var gateDeadline = Date.distantPast
    private var idleWork: DispatchWorkItem?
    private var generation = 0
    private var peaks: [Float] = [0.02, 0.02, 0.02, 0.02]
    private var risePeaks: [Float] = [0.01, 0.01, 0.01, 0.01]
    private var averages: [Float] = [0, 0, 0, 0]
    private var bassA = Biquad.lowPass(140)
    private var bassB = Biquad.lowPass(140)
    private var lowMidBand = Biquad.bandPass(350, q: 0.9)
    private var midBand = Biquad.bandPass(1_500, q: 0.8)
    private var trebleA = Biquad.highPass(5_000)
    private var trebleB = Biquad.highPass(5_000)
    private var userVolume: Float = 0.36
    private var fadeLevel: Float = 1
    private var fadeTimer: DispatchSourceTimer?
    private var activity: NSObjectProtocol?
    private var staging = [Float](repeating: 0, count: 4_096)
    private var stagingFill = 0
    private var levelListeners: [UUID: ([Float]) -> Void] = [:]

    func observeLevels(_ handler: @escaping ([Float]) -> Void) -> UUID {
        let token = UUID()
        lock.lock()
        levelListeners[token] = handler
        lock.unlock()
        return token
    }

    func stopObservingLevels(_ token: UUID) {
        lock.lock()
        levelListeners[token] = nil
        lock.unlock()
    }

    private func broadcast(_ levels: [Float]) {
        lock.lock()
        let handlers = Array(levelListeners.values)
        lock.unlock()
        for handler in handlers { handler(levels) }
    }

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

    func interrupt(for seconds: Double = 0.12) {
        lock.lock()
        gated = true
        gateDeadline = Date().addingTimeInterval(seconds)
        cutPending = true
        lock.unlock()
        fade(to: 0, over: 0.04) { [weak self] in self?.cutIfPending() }
    }

    func react(to event: String) {
        switch event {
        case "seeked": seeked()
        case "track_changed": reopen(discardingStaged: true)
        case "playing": reopen(discardingStaged: false)
        default: break
        }
    }

    var renderedRecently: Bool {
        lock.lock()
        defer { lock.unlock() }
        return CFAbsoluteTimeGetCurrent() - lastRendered < 2
    }

    func drain() {
        lock.lock()
        draining = true
        lock.unlock()
        control.sync { node.stop() }
    }

    func accept() {
        lock.lock()
        draining = false
        lock.unlock()
    }

    private func seeked() {
        lock.lock()
        let wasGated = gated
        lock.unlock()
        if wasGated {
            reopen(discardingStaged: true)
        } else {
            control.sync { cut() }
            lock.lock()
            discardStaged = true
            lock.unlock()
        }
    }

    private func reopen(discardingStaged: Bool) {
        control.sync { cutIfPending() }
        lock.lock()
        gated = false
        if discardingStaged { discardStaged = true }
        lock.unlock()
    }

    private func cutIfPending() {
        lock.lock()
        let pending = cutPending
        cutPending = false
        lock.unlock()
        if pending { cut() }
    }

    private func cut() {
        fadeTimer?.cancel()
        fadeTimer = nil
        node.stop()
        fadeLevel = 1
        applyVolume()
        lock.lock()
        let isHeld = held
        lock.unlock()
        if !isHeld, engine.isRunning { node.play() }
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
        lock.lock()
        if discardStaged {
            discardStaged = false
            stagingFill = 0
        }
        lock.unlock()
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
        lock.lock()
        let wasDraining = draining
        lock.unlock()
        guard !wasDraining else { return }
        slots.wait()
        lock.lock()
        if gated, Date() > gateDeadline { gated = false }
        let dropping = gated || draining
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
            guard let self else { return }
            self.lock.lock()
            self.lastRendered = CFAbsoluteTimeGetCurrent()
            self.lock.unlock()
            self.slots.signal()
            self.broadcast(levels)
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
        var energy: [Float] = [0, 0, 0, 0]
        for i in 0..<frames {
            let m = (left[i] + right[i]) * 0.5
            let bass = bassB.process(bassA.process(m))
            let lowMid = lowMidBand.process(m)
            let mid = midBand.process(m)
            let treble = trebleB.process(trebleA.process(m))
            energy[0] += bass * bass
            energy[1] += lowMid * lowMid
            energy[2] += mid * mid
            energy[3] += treble * treble
        }
        var result: [Float] = [0, 0, 0, 0]
        for band in 0..<4 {
            let rms = (energy[band] / Float(frames)).squareRoot()
            averages[band] += (rms - averages[band]) * 0.06
            let rise = max(0, rms - averages[band] * 1.05)
            peaks[band] = max(rms, peaks[band] * 0.997, 0.0005)
            risePeaks[band] = max(rise, risePeaks[band] * 0.995, 0.0002)
            result[band] = min(0.3 * rms / peaks[band] + 0.7 * rise / risePeaks[band], 1)
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

struct Biquad {
    private var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = Float(b0 / a0)
        self.b1 = Float(b1 / a0)
        self.b2 = Float(b2 / a0)
        self.a1 = Float(a1 / a0)
        self.a2 = Float(a2 / a0)
    }

    private static func parts(_ frequency: Double, q: Double) -> (cos: Double, alpha: Double) {
        let w = 2 * Double.pi * frequency / 44_100
        return (cos(w), sin(w) / (2 * q))
    }

    static func lowPass(_ frequency: Double, q: Double = 0.7071) -> Biquad {
        let (c, alpha) = parts(frequency, q: q)
        return Biquad(b0: (1 - c) / 2, b1: 1 - c, b2: (1 - c) / 2, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    static func highPass(_ frequency: Double, q: Double = 0.7071) -> Biquad {
        let (c, alpha) = parts(frequency, q: q)
        return Biquad(b0: (1 + c) / 2, b1: -(1 + c), b2: (1 + c) / 2, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    static func bandPass(_ frequency: Double, q: Double) -> Biquad {
        let (c, alpha) = parts(frequency, q: q)
        return Biquad(b0: alpha, b1: 0, b2: -alpha, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}
