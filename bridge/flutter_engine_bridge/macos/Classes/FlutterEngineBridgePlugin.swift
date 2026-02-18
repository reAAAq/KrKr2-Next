import Cocoa
import CoreVideo
import FlutterMacOS
import Accelerate

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

public class FlutterEngineBridgePlugin: NSObject, FlutterPlugin {
  private let registrar: FlutterPluginRegistrar
  private var textures: [Int64: EngineHostTexture] = [:]

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
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  deinit {
    for (textureId, _) in textures {
      registrar.textures.unregisterTexture(textureId)
    }
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
            message: "updateTextureRgba requires textureId/rgba/width/height/rowBytes",
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

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
