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

    super.awakeFromNib()
  }
}
