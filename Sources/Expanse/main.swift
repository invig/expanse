import AppKit

// One copy at a time: two would fight over every window (each takes the other's moves for the
// user's and puts windows back). A second launch shows the running copy's welcome window and quits
// before touching anything.
let bundleID = Bundle.main.bundleIdentifier ?? "com.invignation.expanse"
if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .contains(where: { $0.processIdentifier != getpid() && !$0.isTerminated }) {
    // A distributed notification is handed over before we exit (opening a URL isn't).
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.invignation.expanse.showWelcome"),
                                                                 object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
