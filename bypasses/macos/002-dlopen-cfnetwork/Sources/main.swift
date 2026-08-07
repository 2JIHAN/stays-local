// Bypass case 002 — dlopen CFNetwork at runtime.
//
// The app links no networking framework and names no networking symbol at
// build time. It asks the loader for CFNetwork by path and looks its entry
// points up by string, then opens a TCP connection immediately.
//
// Expected verdict: FAIL — it reaches the network.
//
// Static layers 1 (linked frameworks), 2 (referenced symbols), and 3 (remote
// addresses) all PASS: otool -L sees no CFNetwork, nm -u sees no networking
// symbol, and there is no `http(s)://` string. Only the recorded runtime
// socket layer can catch this, and only while the app is actually running.
import Foundation

@main
struct Leak {
    typealias CreatePair = @convention(c) (
        CFAllocator?, CFString, UInt32,
        UnsafeMutablePointer<Unmanaged<CFReadStream>?>?,
        UnsafeMutablePointer<Unmanaged<CFWriteStream>?>?
    ) -> Void
    typealias StreamOpenRead  = @convention(c) (CFReadStream?)  -> Bool
    typealias StreamOpenWrite = @convention(c) (CFWriteStream?) -> Bool

    static func main() {
        // Nothing below is linked or named statically: the loader is handed a
        // path, and every function is resolved by its name as a plain string.
        guard
            let cfnet = dlopen("/System/Library/Frameworks/CFNetwork.framework/CFNetwork", RTLD_NOW),
            let cf    = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW),
            let pSym  = dlsym(cfnet, "CFStreamCreatePairWithSocketToHost"),
            let rSym  = dlsym(cf, "CFReadStreamOpen"),
            let wSym  = dlsym(cf, "CFWriteStreamOpen")
        else { return }

        let createPair = unsafeBitCast(pSym, to: CreatePair.self)
        let readOpen   = unsafeBitCast(rSym, to: StreamOpenRead.self)
        let writeOpen  = unsafeBitCast(wSym, to: StreamOpenWrite.self)

        // A bare host, no scheme, so layer 3's `https?://` grep finds nothing.
        //
        // 192.0.2.1 is TEST-NET-1 (RFC 5737): reserved for documentation and
        // assigned to nobody, so this reaches no real service. A fixture in
        // this corpus must never contact a real server — contributors run
        // these on their own machines, and a catalogue of attacks that
        // performs the attack on a third party is not a test suite.
        //
        // Loopback would be purer still, but a refused connection closes in
        // microseconds and the runtime layer polls twice a second, so it
        // would see nothing and the case would prove less than it should.
        // A reserved address leaves the socket in SYN_SENT for the whole
        // window, which is exactly the state the layer is meant to notice.
        let host = "192.0.2.1" as CFString
        var rs: Unmanaged<CFReadStream>?
        var ws: Unmanaged<CFWriteStream>?
        createPair(nil, host, 80, &rs, &ws)
        guard let readStream  = rs?.takeRetainedValue(),
              let writeStream = ws?.takeRetainedValue() else { return }

        // Schedule and open so the socket is created and the connect begins now.
        CFReadStreamScheduleWithRunLoop(readStream,  CFRunLoopGetCurrent(), CFRunLoopMode.commonModes)
        CFWriteStreamScheduleWithRunLoop(writeStream, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes)
        _ = readOpen(readStream)
        _ = writeOpen(writeStream)

        // Stay alive with the socket open across the 20-second window the
        // recorded runtime layer watches, so that — when it runs — it catches this.
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 30, false)
    }
}
