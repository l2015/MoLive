import Foundation
import Photos
import AVFoundation
import UIKit

extension Converter {
    private actor LivePhotoContinuationHandler {
        private var hasResumed = false
        
        func tryResume<T>(continuation: CheckedContinuation<T, Error>, with value: T) {
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(returning: value)
        }
        
        func tryResumeWithError<T>(continuation: CheckedContinuation<T, Error>, error: Error) {
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(throwing: error)
        }
    }
    
    func createLivePhoto(photoURL: URL, videoURL: URL) async throws -> PHLivePhoto {
        print("开始创建 Live Photo...")
        
        // 读取照片数据
        guard let photoData = try? Data(contentsOf: photoURL),
              let image = UIImage(data: photoData) else {
            throw ConversionError.invalidInput
        }
        
        // 创建 Live Photo
        let handler = LivePhotoContinuationHandler()
        return try await withCheckedThrowingContinuation { continuation in
            PHLivePhoto.request(withResourceFileURLs: [photoURL, videoURL],
                              placeholderImage: image,
                              targetSize: image.size,
                              contentMode: .aspectFit) { [handler] livePhoto, info in
                if let livePhoto = livePhoto {
                    print("Live Photo创建成功")
                    Task {
                        await handler.tryResume(continuation: continuation, with: livePhoto)
                    }
                } else {
                    print("Live Photo创建失败")
                    Task {
                        await handler.tryResumeWithError(continuation: continuation,
                                                       error: ConversionError.conversionFailed)
                    }
                }
            }
        }
    }
    
    func saveLivePhotoToLibrary(photoURL: URL, videoURL: URL) async throws {
        guard await checkPhotoLibraryPermission() else {
            throw ConversionError.noPermission
        }
        
        print("开始生成 Live Photo...")
        
        // 1. 生成 Live Photo 资源
        let resources = try await generateLivePhotoResources(from: photoURL, videoURL: videoURL)
        
        // 2. 保存到相册
        print("开始保存到相册...")
        try await saveLivePhotoResources(resources)
        
        // 3. 清理临时文件
        try? FileManager.default.removeItem(at: resources.pairedImage)
        try? FileManager.default.removeItem(at: resources.pairedVideo)
        
        print("Live Photo保存成功")
    }
    
    private func generateLivePhotoResources(from photoURL: URL, videoURL: URL) async throws -> LivePhotoResources {
        // 1. 创建临时目录
        let tempDirectory = try createTempDirectory(prefix: "LivePhotoTemp")
        
        // 2. 生成资源标识符
        let assetIdentifier = UUID().uuidString
        
        // 3. 处理照片
        let pairedImageURL = tempDirectory.appendingPathComponent("paired_photo").appendingPathExtension("jpg")
        guard let imageDestination = CGImageDestinationCreateWithURL(pairedImageURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil),
              let imageSource = CGImageSourceCreateWithURL(photoURL as CFURL, nil),
              let imageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              var imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [AnyHashable: Any] else {
            throw ConversionError.conversionFailed
        }
        
        // 添加资源标识符和显示时间
        let assetIdentifierInfo = [
            "17": assetIdentifier,
            "PhotoTime": 0.5  // 设置在视频中间显示照片
        ] as [String : Any]
        imageProperties[kCGImagePropertyMakerAppleDictionary as String] = assetIdentifierInfo
        CGImageDestinationAddImage(imageDestination, imageRef, imageProperties as CFDictionary)
        CGImageDestinationFinalize(imageDestination)
        
        // 4. 处理视频
        let pairedVideoURL = tempDirectory.appendingPathComponent("paired_video").appendingPathExtension("mov")
        let videoAsset = AVURLAsset(url: videoURL)
        
        // 获取视频属性
        let tracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw ConversionError.invalidInput
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        // 创建视频写入器
        let assetWriter = try AVAssetWriter(outputURL: pairedVideoURL, fileType: .mov)
        
        // 设置视频参数
        let videoWriterInput = AVAssetWriterInput(mediaType: .video,
                                                 outputSettings: [
                                                    AVVideoCodecKey: AVVideoCodecType.h264,
                                                    AVVideoWidthKey: naturalSize.width,
                                                    AVVideoHeightKey: naturalSize.height
                                                 ])
        videoWriterInput.transform = transform
        videoWriterInput.expectsMediaDataInRealTime = true
        assetWriter.add(videoWriterInput)
        
        // 添加资源标识符元数据
        let metadataItem = AVMutableMetadataItem()
        metadataItem.key = "com.apple.quicktime.content.identifier" as (NSCopying & NSObjectProtocol)
        metadataItem.keySpace = AVMetadataKeySpace(rawValue: "mdta")
        metadataItem.value = assetIdentifier as (NSCopying & NSObjectProtocol)
        metadataItem.dataType = "com.apple.metadata.datatype.UTF-8"
        assetWriter.metadata = [metadataItem]
        
        // 开始写入视频
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        
        let videoReader = try AVAssetReader(asset: videoAsset)
        let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack,
                                                        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoReader.add(videoReaderOutput)
        videoReader.startReading()
        
        // 写入视频数据
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "com.videowriting.queue")
            videoWriterInput.requestMediaDataWhenReady(on: queue) {
                while videoWriterInput.isReadyForMoreMediaData {
                    if let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() {
                        if !videoWriterInput.append(sampleBuffer) {
                            continuation.resume(throwing: ConversionError.conversionFailed)
                            return
                        }
                    } else {
                        videoWriterInput.markAsFinished()
                        assetWriter.finishWriting {
                            if assetWriter.status == .completed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: ConversionError.conversionFailed)
                            }
                        }
                        return
                    }
                }
            }
        }
        
        return (pairedImageURL, pairedVideoURL)
    }
    
    private func saveLivePhotoResources(_ resources: LivePhotoResources) async throws {
        try PHPhotoLibrary.shared().performChangesAndWait {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = true
            request.addResource(with: .photo, fileURL: resources.pairedImage, options: options)
            request.addResource(with: .pairedVideo, fileURL: resources.pairedVideo, options: options)
        }
    }
    
    func getLivePhotoResources(from livePhoto: PHLivePhoto) async throws -> (photoURL: URL, videoURL: URL) {
        print("开始获取 Live Photo 资源...")
        
        // 使用 FileManager 的临时目录
        let tempDirectory = try createTempDirectory(prefix: "LivePhotoTemp")
        let photoURL = tempDirectory.appendingPathComponent("photo.jpg")
        let videoURL = tempDirectory.appendingPathComponent("video.mov")
        
        let resources = PHAssetResource.assetResources(for: livePhoto)
        
        if resources.isEmpty {
            throw ConversionError.invalidInput
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let resourceManager = PHAssetResourceManager.default()
            let group = DispatchGroup()
            var error: Error?
            var completedResources = Set<PHAssetResourceType>()
            
            for resource in resources {
                group.enter()
                let targetURL = resource.type == .photo ? photoURL : videoURL
                print("正在处理资源：\(resource.type.rawValue)")
                
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true
                
                // 确保目标文件的父目录存在
                try? FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(),
                                                       withIntermediateDirectories: true)
                
                // 如果文件已存在，先删除
                try? FileManager.default.removeItem(at: targetURL)
                
                resourceManager.writeData(for: resource, toFile: targetURL, options: options) { writeError in
                    defer { group.leave() }
                    
                    if let writeError = writeError {
                        error = writeError
                        print("写入资源失败：\(writeError.localizedDescription)")
                    } else {
                        // 验证文件是否成功创建
                        if FileManager.default.fileExists(atPath: targetURL.path) {
                            completedResources.insert(resource.type)
                            print("成功写入资源：\(resource.type.rawValue)")
                        } else {
                            error = ConversionError.conversionFailed
                            print("文件写入失败：文件不存在")
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                if let error = error {
                    // 清理临时文件
                    try? FileManager.default.removeItem(at: tempDirectory)
                    continuation.resume(throwing: error)
                } else if !completedResources.contains(.photo) || !completedResources.contains(.pairedVideo) {
                    // 清理临时文件
                    try? FileManager.default.removeItem(at: tempDirectory)
                    continuation.resume(throwing: ConversionError.invalidInput)
                } else {
                    continuation.resume(returning: (photoURL, videoURL))
                }
            }
        }
    }
} 