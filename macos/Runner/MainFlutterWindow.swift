import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Room for a 12×12 board next to the settings panel.
    let windowFrame = NSRect(x: 80, y: 80, width: 1280, height: 860)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 960, height: 700)
    self.title = "CatPuzzle 主题关卡设计"

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The pattern reference window (lib/references.dart).
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      if let window = controller.view.window {
        window.setFrame(NSRect(x: 0, y: 0, width: 1100, height: 780), display: true)
        window.minSize = NSSize(width: 720, height: 520)
        window.title = "LinkedIn 图案参考"
        window.center()
      }
    }

    super.awakeFromNib()
  }
}
