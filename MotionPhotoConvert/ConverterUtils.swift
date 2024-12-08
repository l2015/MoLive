import Foundation
import Photos
import CoreGraphics

extension Converter {
    // 创建临时目录
    func createTempDirectory(prefix: String) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        return tempDirectory
    }
    
    // 权限检查方法
    func checkPhotoLibraryPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite) == .authorized
            return granted
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

// Optional 扩展
extension Optional {
    func unwrap() throws -> Wrapped {
        guard let value = self else {
            throw ConversionError.invalidInput
        }
        return value
    }
}

// CGImageSource 扩展
extension CGImageSource {
    static func create(with url: URL) -> CGImageSource? {
        return CGImageSourceCreateWithURL(url as CFURL, nil)
    }
} 