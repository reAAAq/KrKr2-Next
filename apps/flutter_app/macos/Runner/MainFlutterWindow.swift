import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let launchArgsChannel = FlutterMethodChannel(
      name: "krkr2next/launch_args",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    launchArgsChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getLaunchArguments":
        result(Array(CommandLine.arguments.dropFirst()))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
