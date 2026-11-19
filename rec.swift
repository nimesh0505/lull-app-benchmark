import AudioToolbox
import AVFoundation
import Foundation

func inputDeviceID(named wanted: String) -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
        return nil
    }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
        return nil
    }
    for id in ids {
        guard deviceName(id) == wanted, inputChannelCount(id) > 0 else { continue }
        return id
    }
    return nil
}

func deviceName(_ id: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &name) { pointer in
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
    }
    return status == noErr ? (name as String) : ""
}

func inputChannelCount(_ id: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
        return 0
    }
    let raw = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(size))
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else {
        return 0
    }
    let list = raw.withMemoryRebound(to: AudioBufferList.self, capacity: 1) { $0.pointee }
    return Int(list.mNumberBuffers)
}

let args = CommandLine.arguments
if args.count != 4 {
    fputs("usage: rec <device-name> <outfile.wav> <seconds>\n", stderr)
    exit(2)
}
let wanted = args[1]
let outPath = args[2]
let seconds = Double(args[3]) ?? 0
let device = inputDeviceID(named: wanted)
guard seconds > 0, wanted == "default" || device != nil else {
    fputs("input device not found: \(wanted)\n", stderr)
    exit(4)
}

let access = DispatchSemaphore(value: 0)
var granted = false
AVCaptureDevice.requestAccess(for: .audio) { ok in
    granted = ok
    access.signal()
}
_ = access.wait(timeout: .now() + 30)
fputs("microphone access: \(granted)\n", stderr)
if !granted { exit(3) }

let engine = AVAudioEngine()
let input = engine.inputNode
if wanted != "default" {
    guard let unit = input.audioUnit else {
        fputs("no input audio unit\n", stderr)
        exit(5)
    }
    guard var selected = device else { exit(4) }
    let setStatus = AudioUnitSetProperty(
        unit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &selected,
        UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    if setStatus != noErr {
        fputs("could not select device, status \(setStatus)\n", stderr)
        exit(5)
    }
}

let format = input.outputFormat(forBus: 0)
fputs(
    "tap format: \(format.channelCount) ch, \(format.sampleRate) Hz, \(format.commonFormat.rawValue)\n",
    stderr
)
if format.channelCount == 0 || format.sampleRate == 0 {
    fputs("device has no input format\n", stderr)
    exit(5)
}

let url = URL(fileURLWithPath: outPath)
if FileManager.default.fileExists(atPath: outPath) {
    try? FileManager.default.removeItem(at: url)
}
final class FileBox {
    var file: AVAudioFile?
}

let box = FileBox()
box.file = try AVAudioFile(forWriting: url, settings: format.settings)
let lock = NSLock()
let frames = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
frames.initialize(to: 0)
defer { frames.deallocate() }
input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
    lock.lock()
    defer { lock.unlock() }
    do {
        try box.file?.write(from: buffer)
        frames.pointee += Int64(buffer.frameLength)
    } catch {
        fputs("write error: \(error)\n", stderr)
    }
}
// A sink pulls the microphone without playing it out the speakers.
let sink = AVAudioSinkNode { _, _, _ in noErr }
engine.attach(sink)
engine.connect(input, to: sink, format: format)
try engine.start()
fputs("engine running: \(engine.isRunning)\n", stderr)
let until = Date().addingTimeInterval(seconds)
while Date() < until {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
}
let captured = frames.pointee
engine.inputNode.removeTap(onBus: 0)
engine.stop()
box.file = nil
fputs("captured \(captured) frames\n", stderr)
