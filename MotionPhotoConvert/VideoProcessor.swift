import Foundation
import AVFoundation
import Photos

extension Converter {
    func processVideo(from data: Data, to outputURL: URL) async throws -> CMTime {
        print("开始处理视频数据...")
        
        // 创建临时文件来存储原始视频数据
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_\(UUID().uuidString).mov")
        print("创建临时视频文件：\(tempURL.path)")
        
        do {
            try data.write(to: tempURL)
            print("成功写入临时视频数据，大小：\(data.count) 字节")
            
            // 创建AVAsset
            let asset = AVURLAsset(url: tempURL)
            print("创建AVAsset成功")
            
            // 获取视频时长
            let duration = try await asset.load(.duration)
            print("视频时长：\(CMTimeGetSeconds(duration)) 秒")
            
            // 创建导出会话
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                print("错误：无法创建导出会话")
                throw ConversionError.videoCreationFailed
            }
            print("创建导出会话成功")
            
            // 设置导出参数
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mov
            exportSession.shouldOptimizeForNetworkUse = true
            
            // 设置时间范围
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            exportSession.timeRange = timeRange
            
            print("开始导出视频...")
            // 执行导出
            try await exportSession.export(to: outputURL, as: .mov)
            print("视频导出成功")
            
            // 验证输出文件
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                print("错误：输出视频文件不存在")
                throw ConversionError.videoCreationFailed
            }
            
            let outputFileSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64 ?? 0
            print("输出视频文件大小：\(outputFileSize) 字节")
            
            // 清理临时文件
            try? FileManager.default.removeItem(at: tempURL)
            print("清理临时文件成功")
            
            return duration
            
        } catch {
            // 清理临时文件
            try? FileManager.default.removeItem(at: tempURL)
            print("视频处理失败：\(error.localizedDescription)")
            throw error
        }
    }
    
    func processVideoForMotionJPEG(from url: URL) async throws -> Data {
        print("开始处理视频数据用于 Motion JPEG...")
        
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        
        // 创建临时输出路径
        let tempOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("temp_video_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        
        // 创建导出会话
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ConversionError.videoCreationFailed
        }
        
        // 设置导出参数
        exportSession.outputURL = tempOutputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        print("开始转码视频...")
        // 执行导出
        try await exportSession.export(to: tempOutputURL, as: .mp4)
        print("视频转码成功")
        
        // 读取转码后的视频数据
        let videoData = try Data(contentsOf: tempOutputURL)
        print("视频转码完成，大小：\(videoData.count) 字节")
        
        // 清理临时文件
        try? FileManager.default.removeItem(at: tempOutputURL)
        
        return videoData
    }
    
    func getPairedVideoURL(for photoURL: URL) async throws -> URL {
        // 获取照片文件名（不包含扩展名）
        let photoFileName = photoURL.deletingPathExtension().lastPathComponent
        
        // 获取照片所在目录
        let directory = photoURL.deletingLastPathComponent()
        
        // 查找匹配的视频文件
        let videoExtensions = ["mov", "mp4"]
        let fileManager = FileManager.default
        
        let directoryContents = try fileManager.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])
        
        for url in directoryContents {
            let fileName = url.deletingPathExtension().lastPathComponent
            let fileExtension = url.pathExtension.lowercased()
            
            if fileName == photoFileName && videoExtensions.contains(fileExtension) {
                return url
            }
        }
        
        throw ConversionError.invalidInput
    }
} 