import Accelerate
import Cocoa
import CoreVideo
import FlutterMacOS

private final class EngineHostTexture: NSObject, FlutterTexture {
  private let lock = NSLock()
  private var pixelBuffer: CVPixelBuffer?
  private var pixelWidth: Int = 0
  private var pixelHeight: Int = 0

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard let pixelBuffer else {
      return nil
    }
    return Unmanaged.passRetained(pixelBuffer)
  }

  func updateFrame(
    rgbaData: Data,
    width: Int,
    height: Int,
    rowBytes: Int
  ) -> Bool {
    guard width > 0, height > 0, rowBytes >= width * 4 else {
      return false
    }

    lock.lock()
    if pixelBuffer == nil || pixelWidth != width || pixelHeight != height {
      var buffer: CVPixelBuffer?
      let attrs: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        kCVPixelBufferIOSurfacePropertiesKey: [:],
      ]
      let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attrs as CFDictionary,
        &buffer
      )
      guard status == kCVReturnSuccess, let newBuffer = buffer else {
        lock.unlock()
        return false
      }
      pixelBuffer = newBuffer
      pixelWidth = width
      pixelHeight = height
    }
    guard let pixelBuffer else {
      lock.unlock()
      return false
    }
    lock.unlock()

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      return false
    }
    let targetStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    return rgbaData.withUnsafeBytes { bytes in
      guard let srcBase = bytes.baseAddress else {
        return false
      }
      var srcBuffer = vImage_Buffer(
        data: UnsafeMutableRawPointer(mutating: srcBase),
        height: vImagePixelCount(height),
        width: vImagePixelCount(width),
        rowBytes: rowBytes
      )
      var dstBuffer = vImage_Buffer(
        data: baseAddress,
        height: vImagePixelCount(height),
        width: vImagePixelCount(width),
        rowBytes: targetStride
      )
      var map: [UInt8] = [2, 1, 0, 3]  // RGBA -> BGRA
      let convertResult = vImagePermuteChannels_ARGB8888(
        &srcBuffer,
        &dstBuffer,
        &map,
        vImage_Flags(kvImageNoFlags)
      )
      return convertResult == kvImageNoError
    }
  }
}

private final class EngineNativeSurfaceView: NSView {
  private let viewId: Int64
  private let onDispose: (Int64) -> Void
  private var nativeWindow: NSWindow?
  private var hostWindowObservers: [NSObjectProtocol] = []
  private var clipViewObserver: NSObjectProtocol?
  private weak var observedClipView: NSClipView?
  private var frameSyncScheduled = false

  init(viewId: Int64, onDispose: @escaping (Int64) -> Void) {
    self.viewId = viewId
    self.onDispose = onDispose
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    removeHostObservers()
    removeClipViewObserver()
    detachNativeWindow()
    onDispose(viewId)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil {
      removeHostObservers()
      removeClipViewObserver()
      detachNativeWindow()
      return
    }
    installHostObservers()
    updateClipViewObserver()
    attachToHostWindowIfPossible()
    updateNativeWindowFrame()
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    updateClipViewObserver()
    scheduleNativeWindowFrameUpdate()
  }

  override func layout() {
    super.layout()
    updateClipViewObserver()
    scheduleNativeWindowFrameUpdate()
  }

  func attachNativeWindow(_ window: NSWindow) {
    if nativeWindow === window {
      installHostObservers()
      updateClipViewObserver()
      attachToHostWindowIfPossible()
      scheduleNativeWindowFrameUpdate()
      return
    }

    detachNativeWindow()
    nativeWindow = window
    configureNativeWindow(window)
    installHostObservers()
    updateClipViewObserver()
    attachToHostWindowIfPossible()
    updateNativeWindowFrame()
    window.orderFront(nil)
  }

  func detachNativeWindow() {
    guard let nativeWindow else {
      return
    }
    if let parentWindow = nativeWindow.parent {
      parentWindow.removeChildWindow(nativeWindow)
    }
    nativeWindow.orderOut(nil)
    self.nativeWindow = nil
  }

  private func attachToHostWindowIfPossible() {
    guard let hostWindow = window, let nativeWindow else {
      return
    }

    if nativeWindow.parent !== hostWindow {
      if let parentWindow = nativeWindow.parent {
        parentWindow.removeChildWindow(nativeWindow)
      }
      hostWindow.addChildWindow(nativeWindow, ordered: .above)
    }
  }

  private func scheduleNativeWindowFrameUpdate() {
    guard !frameSyncScheduled else {
      return
    }
    frameSyncScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      self.frameSyncScheduled = false
      self.updateNativeWindowFrame()
    }
  }

  private func updateNativeWindowFrame() {
    guard let hostWindow = window, let nativeWindow else {
      return
    }

    let rectInWindow = convert(bounds, to: nil)
    let rectOnScreen = hostWindow.convertToScreen(rectInWindow).integral
    if nativeWindow.frame.equalTo(rectOnScreen) {
      return
    }
    nativeWindow.setFrame(rectOnScreen, display: true, animate: false)
  }

  private func configureNativeWindow(_ window: NSWindow) {
    var styleMask = window.styleMask
    styleMask.remove([.titled, .closable, .miniaturizable, .resizable])
    styleMask.insert(.borderless)
    window.styleMask = styleMask
    window.hasShadow = false
    window.backgroundColor = .black
    window.isMovable = false
    window.level = .normal
    window.collectionBehavior.insert(.fullScreenAuxiliary)
  }

  private func installHostObservers() {
    removeHostObservers()
    guard let hostWindow = window else {
      return
    }
    let center = NotificationCenter.default
    let names: [Notification.Name] = [
      NSWindow.didMoveNotification,
      NSWindow.didResizeNotification,
      NSWindow.didChangeScreenNotification,
      NSWindow.didEndLiveResizeNotification,
      NSWindow.didDeminiaturizeNotification,
    ]
    hostWindowObservers = names.map { name in
      center.addObserver(forName: name, object: hostWindow, queue: .main) {
        [weak self] _ in
        self?.scheduleNativeWindowFrameUpdate()
      }
    }
  }

  private func removeHostObservers() {
    let center = NotificationCenter.default
    for observer in hostWindowObservers {
      center.removeObserver(observer)
    }
    hostWindowObservers.removeAll()
  }

  private func updateClipViewObserver() {
    let clipView = enclosingScrollView?.contentView
    if observedClipView === clipView {
      return
    }
    removeClipViewObserver()
    guard let clipView else {
      return
    }
    clipView.postsBoundsChangedNotifications = true
    observedClipView = clipView
    clipViewObserver = NotificationCenter.default.addObserver(
      forName: NSView.boundsDidChangeNotification,
      object: clipView,
      queue: .main
    ) { [weak self] _ in
      self?.scheduleNativeWindowFrameUpdate()
    }
  }

  private func removeClipViewObserver() {
    if let observer = clipViewObserver {
      NotificationCenter.default.removeObserver(observer)
      clipViewObserver = nil
    }
    observedClipView = nil
  }
}

private final class EngineNativeSurfaceFactory: NSObject, FlutterPlatformViewFactory
{
  private let onCreate: (Int64, EngineNativeSurfaceView) -> Void
  private let onDispose: (Int64) -> Void

  init(
    onCreate: @escaping (Int64, EngineNativeSurfaceView) -> Void,
    onDispose: @escaping (Int64) -> Void
  ) {
    self.onCreate = onCreate
    self.onDispose = onDispose
    super.init()
  }

  func createArgsCodec() -> (NSObjectProtocol & FlutterMessageCodec)? {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withViewIdentifier viewId: Int64,
    arguments _: Any?
  ) -> NSView {
    let nativeSurfaceView = EngineNativeSurfaceView(
      viewId: viewId,
      onDispose: onDispose
    )
    onCreate(viewId, nativeSurfaceView)
    return nativeSurfaceView
  }
}

public class FlutterEngineBridgePlugin: NSObject, FlutterPlugin {
  private static let nativeSurfaceViewType =
    "flutter_engine_bridge/native_engine_surface"

  private let registrar: FlutterPluginRegistrar
  private var textures: [Int64: EngineHostTexture] = [:]
  private var nativeSurfaceViews: [Int64: EngineNativeSurfaceView] = [:]
  private var nativeSurfaceFactory: EngineNativeSurfaceFactory?

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_engine_bridge",
      binaryMessenger: registrar.messenger
    )
    let instance = FlutterEngineBridgePlugin(registrar: registrar)
    instance.registerNativeSurfaceFactory()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  deinit {
    for (textureId, _) in textures {
      registrar.textures.unregisterTexture(textureId)
    }
    for (_, nativeSurfaceView) in nativeSurfaceViews {
      nativeSurfaceView.detachNativeWindow()
    }
    nativeSurfaceViews.removeAll()
  }

  private func registerNativeSurfaceFactory() {
    let factory = EngineNativeSurfaceFactory(
      onCreate: { [weak self] viewId, nativeSurfaceView in
        self?.nativeSurfaceViews[viewId] = nativeSurfaceView
      },
      onDispose: { [weak self] viewId in
        self?.nativeSurfaceViews.removeValue(forKey: viewId)
      }
    )
    nativeSurfaceFactory = factory
    registrar.register(factory, withId: Self.nativeSurfaceViewType)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)

    case "createTexture":
      let texture = EngineHostTexture()
      let textureId = registrar.textures.register(texture)
      textures[textureId] = texture
      result(textureId)

    case "updateTextureRgba":
      guard let args = call.arguments as? [String: Any],
        let textureIdNumber = args["textureId"] as? NSNumber,
        let rgba = args["rgba"] as? FlutterStandardTypedData,
        let widthNumber = args["width"] as? NSNumber,
        let heightNumber = args["height"] as? NSNumber,
        let rowBytesNumber = args["rowBytes"] as? NSNumber
      else {
        result(
          FlutterError(
            code: "invalid_args",
            message:
              "updateTextureRgba requires textureId/rgba/width/height/rowBytes",
            details: nil
          )
        )
        return
      }

      let textureId = textureIdNumber.int64Value
      let width = widthNumber.intValue
      let height = heightNumber.intValue
      let rowBytes = rowBytesNumber.intValue
      guard let texture = textures[textureId] else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "Texture id not found",
            details: nil
          )
        )
        return
      }

      guard texture.updateFrame(
        rgbaData: rgba.data,
        width: width,
        height: height,
        rowBytes: rowBytes
      ) else {
        result(
          FlutterError(
            code: "texture_update_failed",
            message: "Failed to update texture frame",
            details: nil
          )
        )
        return
      }

      registrar.textures.textureFrameAvailable(textureId)
      result(nil)

    case "disposeTexture":
      guard let args = call.arguments as? [String: Any],
        let textureIdNumber = args["textureId"] as? NSNumber
      else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "disposeTexture requires textureId",
            details: nil
          )
        )
        return
      }
      let textureId = textureIdNumber.int64Value
      textures.removeValue(forKey: textureId)
      registrar.textures.unregisterTexture(textureId)
      result(nil)

    case "attachNativeWindow":
      guard let args = call.arguments as? [String: Any],
        let viewIdNumber = args["viewId"] as? NSNumber,
        let windowHandleNumber = args["windowHandle"] as? NSNumber
      else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "attachNativeWindow requires viewId/windowHandle",
            details: nil
          )
        )
        return
      }

      let viewId = viewIdNumber.int64Value
      guard let nativeSurfaceView = nativeSurfaceViews[viewId] else {
        result(
          FlutterError(
            code: "surface_not_found",
            message: "native surface view not found",
            details: nil
          )
        )
        return
      }

      let windowHandle = windowHandleNumber.uint64Value
      guard let rawPointer = UnsafeRawPointer(bitPattern: UInt(windowHandle))
      else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "windowHandle is invalid",
            details: nil
          )
        )
        return
      }
      let nativeWindow = Unmanaged<NSWindow>.fromOpaque(rawPointer)
        .takeUnretainedValue()
      nativeSurfaceView.attachNativeWindow(nativeWindow)
      result(nil)

    case "detachNativeWindow":
      guard let args = call.arguments as? [String: Any],
        let viewIdNumber = args["viewId"] as? NSNumber
      else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "detachNativeWindow requires viewId",
            details: nil
          )
        )
        return
      }

      let viewId = viewIdNumber.int64Value
      guard let nativeSurfaceView = nativeSurfaceViews[viewId] else {
        result(nil)
        return
      }
      nativeSurfaceView.detachNativeWindow()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
