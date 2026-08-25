import CoreGraphics
import Foundation

// Bindings to SkyLight, the private window-server framework (the modern rename of the old CGS*
// API). No headers ship for any of this. Every symbol below was confirmed present in
// /System/Library/PrivateFrameworks/SkyLight.framework on macOS 26.5 by dumping its exports;
// the *signatures*, however, come from community reverse engineering and are not guaranteed.
// Breakage on a macOS update should be expected rather than surprising — Tahoe is visibly
// mid-migration here, shipping SLSBridged*Operation Objective-C wrappers beside these C entry
// points.
//
// Why this exists: `.canJoinAllSpaces` makes a window an all-Spaces *floater* that belongs to no
// individual Space's z-order, so the window server composites it at the front of its level every
// time you switch Space. Adding the window to each Space explicitly makes it a real member with
// its own z-order slot in each one, so switching Space is not an "arrival" and there is nothing
// to flash.
//
// Symbols are resolved with dlsym rather than linked: SkyLight exists only in the dyld shared
// cache, so there is nothing to link against, and a missing symbol then degrades to "unavailable"
// instead of failing to launch.

enum SkyLight {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias AddWindowsToSpaces = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias CopySpacesForWindows =
        @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SetWindowLevel = @convention(c) (Int32, UInt32, Int32) -> Int32
    private typealias SetWindowEventMask = @convention(c) (Int32, UInt32, UInt32) -> Int32
    private typealias GetWindowEventMask =
        @convention(c) (Int32, UInt32, UnsafeMutablePointer<UInt32>) -> Int32

    /// Community headers call this `kCGSAllSpacesMask`: current | others | user.
    private static let allSpacesSelector: Int32 = 7

    nonisolated(unsafe) private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY
    )

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: T.self)
    }

    private static let mainConnectionID: MainConnectionID? =
        symbol("SLSMainConnectionID")
    private static let copyManagedDisplaySpaces: CopyManagedDisplaySpaces? =
        symbol("SLSCopyManagedDisplaySpaces")
    private static let addWindowsToSpaces: AddWindowsToSpaces? =
        symbol("SLSAddWindowsToSpaces")
    private static let copySpacesForWindows: CopySpacesForWindows? =
        symbol("SLSCopySpacesForWindows")
    // `SLSGetWindowLevel` is deliberately not bound. It exists, but the obvious
    // (cid, wid, out) -> err signature reports the wrong value, and `kCGWindowLayer` only ever
    // reports the level the owner *declared* — so in widget mode neither can confirm where the
    // window actually composites. Trusting either produced a wrong conclusion once already.
    private static let setWindowLevel: SetWindowLevel? = symbol("SLSSetWindowLevel")
    private static let setWindowEventMask: SetWindowEventMask? = symbol("SLSSetWindowEventMask")
    private static let getWindowEventMask: GetWindowEventMask? = symbol("SLSGetWindowEventMask")

    /// False when any symbol we depend on is missing, so callers can fall back to plain AppKit.
    static var isAvailable: Bool {
        mainConnectionID != nil && copyManagedDisplaySpaces != nil && addWindowsToSpaces != nil
            && copySpacesForWindows != nil && setWindowLevel != nil && setWindowEventMask != nil
    }

    static var connection: Int32 { mainConnectionID?() ?? 0 }

    struct Space {
        let id: UInt64
        /// 0 for an ordinary user Space; non-zero for fullscreen and tiled Spaces.
        let type: Int

        var isUserSpace: Bool { type == 0 }
    }

    /// Every Space across every display, flattened.
    ///
    /// `SLSCopyManagedDisplaySpaces` returns one dictionary per display, each holding a
    /// `"Spaces"` array whose entries carry an `"id64"` identifier and a `"type"`.
    static func allSpaces() -> [Space] {
        guard let displays = copyManagedDisplaySpaces?(connection)?
            .takeRetainedValue() as? [[String: Any]]
        else { return [] }

        return displays.flatMap { display -> [Space] in
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            return spaces.compactMap { entry in
                guard let id = (entry["id64"] as? NSNumber)?.uint64Value else { return nil }
                return Space(id: id, type: (entry["type"] as? NSNumber)?.intValue ?? 0)
            }
        }
    }

    static func add(window: Int, to spaces: [UInt64]) {
        guard !spaces.isEmpty else { return }
        addWindowsToSpaces?(
            connection,
            [NSNumber(value: window)] as CFArray,
            spaces.map { NSNumber(value: $0) } as CFArray
        )
    }

    /// Mouse events the window should keep receiving. `SLSSetWindowEventMask` takes a bitmask
    /// indexed by `CGEventType` raw values, same convention as `CGEventMask`.
    static let mouseEventMask: UInt32 = {
        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .mouseMoved, .scrollWheel,
        ]
        return types.reduce(0) { $0 | (1 << UInt32($1.rawValue)) }
    }()

    /// Sets the level the *window server* uses, independently of `NSWindow.level`.
    ///
    /// This is the whole point of the exercise: AppKit couples "how low the window sits" to
    /// "whether it gets mouse events", and below `.normal` you lose input. Setting the server
    /// level directly, while AppKit still believes the window is at `.normal`, is the only way to
    /// ask for one without the other.
    @discardableResult
    static func setLevel(_ level: Int32, forWindow window: Int) -> Int32 {
        setWindowLevel?(connection, UInt32(window), level) ?? -1
    }

    /// Adds bits to the window's event mask. Never assign a mask outright: the default carries
    /// far more than mouse input (3999072222 on macOS 26.5), and replacing it silently strips
    /// everything else the window relies on.
    @discardableResult
    static func addEventMask(_ mask: UInt32, forWindow window: Int) -> Int32 {
        let combined = (eventMask(forWindow: window) ?? 0) | mask
        return setWindowEventMask?(connection, UInt32(window), combined) ?? -1
    }

    static func eventMask(forWindow window: Int) -> UInt32? {
        var mask: UInt32 = 0
        guard let getWindowEventMask,
              getWindowEventMask(connection, UInt32(window), &mask) == 0 else { return nil }
        return mask
    }

    /// Which Spaces the window server currently considers this window a member of. Reading this
    /// back is how membership is verified without switching Space by hand.
    static func spaces(forWindow window: Int) -> [UInt64] {
        guard let result = copySpacesForWindows?(
            connection, allSpacesSelector, [NSNumber(value: window)] as CFArray
        )?.takeRetainedValue() as? [NSNumber] else { return [] }

        return result.map { $0.uint64Value }
    }
}
