import Foundation

// Launched on demand by launchd as root (see the LaunchDaemons plist embedded
// in the app bundle). All work happens in response to XPC messages.
let service = HelperService()
let listener = NSXPCListener(machServiceName: kMachServiceName)
listener.delegate = service
listener.resume()
RunLoop.main.run()
