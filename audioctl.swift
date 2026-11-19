import AudioToolbox
import Foundation

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
    for id in ids where deviceName(id) == wanted {
        return id
    }
    return nil
}

func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &id
    )
    if status != noErr { fputs("could not read default device\n", stderr); exit(1) }
    return id
}

func defaultInput() -> AudioDeviceID {
    defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
}

func defaultOutput() -> AudioDeviceID {
    defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
}

func setDefaultDevice(_ selector: AudioObjectPropertySelector, _ id: AudioDeviceID) {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var selected = id
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        size,
        &selected
    )
    if status != noErr {
        fputs("could not set default device, status \(status)\n", stderr)
        exit(1)
    }
}

func setDefaultInput(_ id: AudioDeviceID) {
    setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, id)
}

func setDefaultOutput(_ id: AudioDeviceID) {
    setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, id)
}

let args = CommandLine.arguments
switch args.count {
case 2 where args[1] == "get-input":
    print(deviceName(defaultInput()))
case 2 where args[1] == "get-output":
    print(deviceName(defaultOutput()))
case 3 where args[1] == "set-input":
    guard let id = inputDeviceID(named: args[2]) else {
        fputs("no device named \(args[2])\n", stderr)
        exit(4)
    }
    setDefaultInput(id)
    let now = deviceName(defaultInput())
    if now != args[2] {
        fputs("default input is \(now), not \(args[2])\n", stderr)
        exit(5)
    }
    print(now)
case 3 where args[1] == "set-output":
    guard let id = inputDeviceID(named: args[2]) else {
        fputs("no device named \(args[2])\n", stderr)
        exit(4)
    }
    setDefaultOutput(id)
    let now = deviceName(defaultOutput())
    if now != args[2] {
        fputs("default output is \(now), not \(args[2])\n", stderr)
        exit(5)
    }
    print(now)
default:
    fputs("usage: audioctl get-input | get-output | set-input <name> | set-output <name>\n", stderr)
    exit(2)
}
