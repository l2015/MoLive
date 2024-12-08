import Foundation
import Photos
import UIKit

class MotionJPEGToLiveConverter {
    static let shared = MotionJPEGToLiveConverter()
    private init() {}
    
    func convert(from url: URL) async throws {
        // 检查权限状态
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        // 如果不是完全授权，请求权限
        if status != .authorized {
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if newStatus != .authorized {
                throw NSError(domain: "PhotoConverterError",
                            code: 1001,
                            userInfo: [NSLocalizedDescriptionKey: "需要完整的相册访问权限"])
            }
        }
        
        // 转换并保存
        _ = try await Converter.shared.convertMotionJPEGToLivePhoto(from: url)
    }
} 