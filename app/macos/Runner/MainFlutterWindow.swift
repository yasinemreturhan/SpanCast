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

    let virtualDisplayChannel = FlutterMethodChannel(name: "app.doscreen/virtual_display", binaryMessenger: flutterViewController.engine.binaryMessenger)
    virtualDisplayChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "isSupported":
        result(VirtualDisplayManager.shared.isSupported)
      case "isActive":
        result(VirtualDisplayManager.shared.isActive)
      case "create":
        let success = VirtualDisplayManager.shared.createDisplay()
        result(success)
      case "destroy":
        VirtualDisplayManager.shared.destroyDisplay()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

final class VirtualDisplayManager {
  static let shared = VirtualDisplayManager()
  private var activeDisplay: AnyObject?

  var isSupported: Bool {
    return NSClassFromString("CGVirtualDisplay") != nil &&
           NSClassFromString("CGVirtualDisplayDescriptor") != nil &&
           NSClassFromString("CGVirtualDisplayMode") != nil &&
           NSClassFromString("CGVirtualDisplaySettings") != nil
  }

  var isActive: Bool {
    return activeDisplay != nil
  }

  func createDisplay(width: UInt32 = 1920, height: UInt32 = 1080, refreshRate: Double = 60.0) -> Bool {
    guard isSupported else { return false }
    destroyDisplay()

    guard let descClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
          let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
          let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
          let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type else {
      return false
    }

    let descriptor = descClass.init()
    if descriptor.responds(to: Selector(("setName:"))) {
      descriptor.setValue("DoScreen 2. Ekran", forKey: "name")
    }
    if descriptor.responds(to: Selector(("setQueue:"))) {
      descriptor.setValue(DispatchQueue.main, forKey: "queue")
    } else if descriptor.responds(to: Selector(("setDispatchQueue:"))) {
      descriptor.setValue(DispatchQueue.main, forKey: "dispatchQueue")
    }
    if descriptor.responds(to: Selector(("setMaxPixelsWide:"))) {
      descriptor.setValue(3840, forKey: "maxPixelsWide")
    }
    if descriptor.responds(to: Selector(("setMaxPixelsHigh:"))) {
      descriptor.setValue(2160, forKey: "maxPixelsHigh")
    }
    if descriptor.responds(to: Selector(("setSizeInMillimeters:"))) {
      descriptor.setValue(CGSize(width: 530, height: 300), forKey: "sizeInMillimeters")
    }

    let initModeSel = sel_registerName("initWithWidth:height:refreshRate:")
    guard let method = class_getInstanceMethod(modeClass, initModeSel) else { return false }
    let imp = method_getImplementation(method)
    typealias ModeInitFunc = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> AnyObject
    let modeInit = unsafeBitCast(imp, to: ModeInitFunc.self)

    let allocatedMode = modeClass.perform(Selector(("alloc"))).takeRetainedValue()
    let mode = modeInit(allocatedMode, initModeSel, width, height, refreshRate)

    let settings = settingsClass.init()
    if settings.responds(to: Selector(("setModes:"))) {
      settings.setValue([mode], forKey: "modes")
    }
    if settings.responds(to: Selector(("setHiDPI:"))) {
      settings.setValue(1, forKey: "hiDPI")
    }

    let initDisplaySel = sel_registerName("initWithDescriptor:")
    guard let displayMethod = class_getInstanceMethod(displayClass, initDisplaySel) else { return false }
    let displayImp = method_getImplementation(displayMethod)
    typealias DisplayInitFunc = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject?
    let displayInit = unsafeBitCast(displayImp, to: DisplayInitFunc.self)

    let allocatedDisplay = displayClass.perform(Selector(("alloc"))).takeRetainedValue()
    guard let display = displayInit(allocatedDisplay, initDisplaySel, descriptor) else {
      NSLog("DoScreen: CGVirtualDisplay initWithDescriptor returned nil (system denied virtual display creation)")
      return false
    }

    let applySettingsSel = sel_registerName("applySettings:")
    guard let applyMethod = class_getInstanceMethod(displayClass, applySettingsSel) else { return false }
    let applyImp = method_getImplementation(applyMethod)
    typealias ApplySettingsFunc = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
    let applySettings = unsafeBitCast(applyImp, to: ApplySettingsFunc.self)

    let success = applySettings(display, applySettingsSel, settings)
    if success {
      self.activeDisplay = display
      return true
    } else {
      return false
    }
  }

  func destroyDisplay() {
    activeDisplay = nil
  }
}
