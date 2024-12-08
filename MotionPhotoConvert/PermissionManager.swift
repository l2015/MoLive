import Foundation
import Photos
import SwiftUI

class PermissionManager: ObservableObject {
    @Published var photoLibraryPermissionStatus: PHAuthorizationStatus = .notDetermined
    
    init() {
        photoLibraryPermissionStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    func requestPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        // 先检查是否已经被拒绝
        if photoLibraryPermissionStatus == .denied {
            completion(false)
            return
        }
        
        // 如果已经授权，直接返回
        if photoLibraryPermissionStatus == .authorized {
            completion(true)
            return
        }
        
        // 请求新的授权
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.photoLibraryPermissionStatus = status
                let isAuthorized = status == .authorized || status == .limited
                completion(isAuthorized)
            }
        }
    }
}
