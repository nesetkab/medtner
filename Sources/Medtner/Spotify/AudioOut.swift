import AVFoundation
import Foundation

final class AudioOut: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private let slots = DispatchSemaphore(value: 4)
    private let lock = NSLock()
    private let framesPerChunk = 2_048
    private var held = false
    private var idleWork: DispatchWorkItem?
    private var generation = 0

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
            guard !stale, usable > 0, let buffer = convert(chunk.prefix(usable)) else {
                slots.signal()
                if ended || stale {
                    try? handle.close()
                    return
                }
                continue
            }
            node.scheduleBuffer(buffer) { [weak self] in self?.slots.signal() }
            ensureRunning()
            if ended {
                try? handle.close()
                return
            }
        }
    }

    private func convert(_ data: Data) -> AVAudioPCMBuffer? {
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
        return buffer
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
