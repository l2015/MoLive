import Foundation
import UIKit
import PhotosUI
import SwiftUI

enum ConvertMode {
    case motionJPEGToLive
    case liveToMotionJPEG
    
    var title: String {
        switch self {
        case .motionJPEGToLive:
            return "Motion JPEG → Live Photo"
        case .liveToMotionJPEG:
            return "Live Photo → Motion JPEG"
        }
    }
}

class ConversionState: ObservableObject {
    @Published var selectedItems: [PhotosPickerItem] = []
    @Published var selectedPhotos: [UIImage] = []
    @Published var selectedURLs: [URL] = []
    @Published var isConverting = false
    @Published var conversionProgress: Double = 0
    @Published var convertMode: ConvertMode = .motionJPEGToLive
    
    func reset() {
        selectedItems.removeAll()
        selectedPhotos.removeAll()
        selectedURLs.removeAll()
        conversionProgress = 0
        isConverting = false
    }
} 