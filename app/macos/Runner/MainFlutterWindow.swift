import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let windowChannel = FlutterMethodChannel(name: "app.doscreen/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(FlutterError(code: "UNAVAILABLE", message: "Window unavailable", details: nil))
        return
      }
      switch call.method {
      case "toggleFullScreen":
        self.toggleFullScreen(nil)
        result(true)
      case "isFullScreen":
        result(self.styleMask.contains(.fullScreen))
      case "setFullScreen":
        if let args = call.arguments as? [String: Any], let enable = args["enable"] as? Bool {
          let isFS = self.styleMask.contains(.fullScreen)
          if isFS != enable {
            self.toggleFullScreen(nil)
          }
        }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let permissionChannel = FlutterMethodChannel(name: "app.doscreen/macos_permissions", binaryMessenger: flutterViewController.engine.binaryMessenger)
    permissionChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "hasScreenCapturePermission":
        if #available(macOS 10.15, *) {
          result(CGPreflightScreenCaptureAccess())
        } else {
          result(true)
        }
      case "requestScreenCapturePermission":
        if #available(macOS 11.0, *) {
          result(CGRequestScreenCaptureAccess())
        } else {
          result(true)
        }
      case "openScreenCaptureSettings":
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
          NSWorkspace.shared.open(url)
        }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
