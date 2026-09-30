import AVFoundation
import Foundation

final class AudioOut: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private let slots = DispatchSemaphore(value: 8)
    private let lock = NSLock()
    private let framesPerChunk = 2_048
    private var held = false
    private var idleWork: DispatchWorkItem?
    private var generation = 0
    private var lows: (Float, Float, Float) = (0, 0, 0)
    private var peaks: [Float] = [0.02, 0.02, 0.02, 0.02]
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
        engine.mainMixerNode.outputVolume = linear * linear
    }

    func hold() {
        lock.lock()
        held = true
        lock.unlock()
        node.pause()
        scheduleIdle()
    }

    func release() {
        lock.lock()
        held = false
        lock.unlock()
        ensureRunning()
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
            lock.unlock()
            let usable = filled - filled % 4
            guard !stale, usable > 0, let (buffer, levels) = convert(chunk.prefix(usable)) else {
                slots.signal()
                if ended || stale {
                    try? handle.close()
                    return
                }
                continue
            }
            node.scheduleBuffer(buffer, completionCallbackType: .dataRendered) { [weak self] _ in
                self?.slots.signal()
                self?.onLevels?(levels)
            }
            ensureRunning()
            if ended {
                try? handle.close()
                return
            }
        }
    }

    private func convert(_ data: Data) -> (AVAudioPCMBuffer, [Float])? {
        let frames = data.count / 4
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        let left = channels[0], right = channels[1]
        var (low, lowMid, mid) = lows
        var energy: [Float] = [0, 0, 0, 0]
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            let scale: Float = 1 / 32_768
            for i in 0..<frames {
                let l = Float(Int16(littleEndian: samples[i * 2])) * scale
                let r = Float(Int16(littleEndian: samples[i * 2 + 1])) * scale
                left[i] = l
                right[i] = r
                let m = (l + r) * 0.5
                low += 0.021 * (m - low)
                lowMid += 0.069 * (m - lowMid)
                mid += 0.248 * (m - mid)
                let bands = (low, lowMid - low, mid - lowMid, m - mid)
                energy[0] += bands.0 * bands.0
                energy[1] += bands.1 * bands.1
                energy[2] += bands.2 * bands.2
                energy[3] += bands.3 * bands.3
            }
        }
        lows = (low, lowMid, mid)
        var levels: [Float] = [0, 0, 0, 0]
        for band in 0..<4 {
            let rms = (energy[band] / Float(frames)).squareRoot()
            peaks[band] = max(rms, peaks[band] * 0.996, 0.002)
            levels[band] = min(rms / peaks[band], 1)
        }
        return (buffer, levels)
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
        }
        if !node.isPlaying { node.play() }
        scheduleIdle()
    }

    private func scheduleIdle() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.node.pause()
            self.engine.pause()
        }
        lock.lock()
        idleWork?.cancel()
        idleWork = work
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func restart() {
        engine.stop()
        engine.connect(node, to: engine.mainMixerNode, format: format)
        ensureRunning()
    }
}
