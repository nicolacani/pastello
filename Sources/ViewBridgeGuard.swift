import AppKit
import ObjectiveC.runtime

/// Safety net for a ViewBridge bug on macOS 26/27 (seen on 26A5388g).
///
/// When the system reconnects the status item's scene — which happens on a
/// Space switch, or when another app goes fullscreen — AppKit reorders the
/// `NSStatusBarWindow` and notifies the app's `NSRemoteView`s. If one of them
/// is left over, already detached from its window, ViewBridge asserts and the
/// process dies with SIGABRT, without a single line of our code in the stack:
///
///     assertion failed: '<NSRemoteView: … com.apple.SafariPlatformSupport.Helper
///     SPCompletionListServiceViewController> notified of <NSStatusBarWindow: …>
///     but expected (null)' in -[NSRemoteView containingWindowWillOrderOnScreen:]
///
/// The remote view at fault is the AutoFill completion list, which macOS
/// creates by itself for any text field that takes focus (verified:
/// `isAutomaticTextCompletionEnabled = false` does not avoid it), so there is
/// no way for an app not to have one.
///
/// The assertion compares the notified window with the remote view's
/// `self.window` (`expected` is exactly that: `(null)` when the view is
/// detached). Here we swap in an implementation that ignores the notification
/// when the two don't match — precisely the cases where the original would
/// abort — and otherwise calls the original. If the class or the method ever
/// go away, `install()` does nothing and returns false.
enum ViewBridgeGuard {

    private static var installed = false

    /// Call once at launch, on the main thread.
    @discardableResult
    static func install() -> Bool {
        guard !installed else { return true }

        // ViewBridge only comes into play when the first remote view is born:
        // at launch the class isn't there yet, and without the class there is
        // nothing to replace. We load it ourselves so the guard is in place
        // before it is needed (from the dyld shared cache: no file to find on
        // disk).
        if NSClassFromString("NSRemoteView") == nil {
            _ = dlopen("/System/Library/PrivateFrameworks/ViewBridge.framework/ViewBridge", RTLD_LAZY)
        }
        guard let cls: AnyClass = NSClassFromString("NSRemoteView") else { return false }

        let sel = NSSelectorFromString("containingWindowWillOrderOnScreen:")
        guard let method = class_getInstanceMethod(cls, sel) else { return false }

        typealias Original = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Original.self)

        let replacement: @convention(block) (AnyObject, AnyObject) -> Void = { view, note in
            let ordered = (note as? NSNotification)?.object as? NSWindow
            let containing = (view as? NSView)?.window
            guard containing === ordered else {
                // This is the case that would abort the app: an orphaned remote
                // view (or one living in another window) told about this
                // window's reordering. There is nothing useful to do: ignore it.
                NSLog("ViewBridgeGuard: ignored the reordering notification for %@ sent to a remote view in %@",
                      String(describing: ordered), String(describing: containing))
                return
            }
            original(view, sel, note)
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
        installed = true
        return true
    }
}
