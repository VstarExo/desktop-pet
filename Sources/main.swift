import AppKit

let arguments = CommandLine.arguments

if let flag = arguments.firstIndex(of: "--poses"), flag + 1 < arguments.count {
    exit(Snapshot.writePoses(to: arguments[flag + 1]) ? 0 : 1)
}
if let flag = arguments.firstIndex(of: "--icon"), flag + 1 < arguments.count {
    exit(Snapshot.writeIcon(to: arguments[flag + 1]) ? 0 : 1)
}

let app = NSApplication.shared
let controller = PetController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
