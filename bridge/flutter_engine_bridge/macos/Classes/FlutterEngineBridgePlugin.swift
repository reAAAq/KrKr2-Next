import Cocoa
import CoreVideo
import FlutterMacOS

private final class EngineHostTexture: NSObject, FlutterTexture {
  private let lock = NSLock()
  private var pixelBuffer: CVPixelBuffer?

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
    guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
      return false
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      return false
    }
    let targetStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    rgbaData.withUnsafeBytes { bytes in
      guard let srcBase = bytes.baseAddress else {
        return
      }
      let srcRows = srcBase.assumingMemoryBound(to: UInt8.self)
      let dstRows = baseAddress.assumingMemoryBound(to: UInt8.self)

      for y in 0..<height {
        let src = srcRows.advanced(by: y * rowBytes)
        let dst = dstRows.advanced(by: y * targetStride)
        for x in 0..<width {
          let idx = x * 4
          let r = src[idx]
          let g = src[idx + 1]
          let b = src[idx + 2]
          let a = src[idx + 3]
          dst[idx] = b
          dst[idx + 1] = g
          dst[idx + 2] = r
          dst[idx + 3] = a
        }
      }
    }

    lock.lock()
    self.pixelBuffer = pixelBuffer
    lock.unlock()
    return true
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
