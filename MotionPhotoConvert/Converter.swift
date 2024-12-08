import Foundation
import Photos
import UIKit
import AVFoundation
import MobileCoreServices
import UniformTypeIdentifiers

class Converter {
    typealias LivePhotoResources = (pairedImage: URL, pairedVideo: URL)
    
    static let shared = Converter()
    private init() {}
}
