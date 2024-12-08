import Foundation
import Photos
import AVFoundation
import UIKit
import UniformTypeIdentifiers

extension Converter {
    func convertMotionJPEGToLivePhoto(from url: URL) async throws -> PHLivePhoto {
        print("开始转换动态照片...")
        
        // 读取文件数据
        let data = try Data(contentsOf: url)
        print("成功读取文件数据，大小：\(data.count) 字节")
        
        // 创建临时目录
        let tempDirectory = try createTempDirectory(prefix: "MotionJPEGConvert")
        let tempPhotoURL = tempDirectory.appendingPathComponent("photo").appendingPathExtension("jpg")
        let tempVideoURL = tempDirectory.appendingPathComponent("video").appendingPathExtension("mov")
        let processedVideoURL = tempDirectory.appendingPathComponent("processed_video").appendingPathExtension("mov")
        
        defer {
            // 清理临时文件
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        
        // 分离图片和视频数据
        try await separateImageAndVideo(from: data, photoURL: tempPhotoURL, videoURL: tempVideoURL)
        
        // 处理视频数据
        let videoData = try Data(contentsOf: tempVideoURL)
        _ = try await processVideo(from: videoData, to: processedVideoURL)
        
        // 创建 Live Photo
        let livePhoto = try await createLivePhoto(photoURL: tempPhotoURL, videoURL: processedVideoURL)
        
        // 保存到相册
        try await saveLivePhotoToLibrary(photoURL: tempPhotoURL, videoURL: processedVideoURL)
        
        return livePhoto
    }
    
    func convertLivePhotoToMotionJPEG(from livePhoto: PHLivePhoto) async throws -> URL {
        print("开始转换 Live Photo...")

        // 创建临时目录
        let tempDirectory = try createTempDirectory(prefix: "LivePhotoConvert")
        let tempJPEGURL = tempDirectory.appendingPathComponent("temp").appendingPathExtension("jpg")
        let outputURL = tempDirectory.appendingPathComponent("MVIMG_\(UUID().uuidString)").appendingPathExtension("jpg")

        do {
            // 获取 Live Photo 资源
            let (photoURL, videoURL) = try await getLivePhotoResources(from: livePhoto)
            defer {
                // 清理资源文件
                try? FileManager.default.removeItem(at: photoURL)
                try? FileManager.default.removeItem(at: videoURL)
            }

            // 读取照片数据和属性
            guard let imageSource = CGImageSourceCreateWithURL(photoURL as CFURL, nil),
                  let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
                  let imageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ConversionError.conversionFailed
            }

            // 将图像转换为高质量JPEG，保留原始属性
            guard let destination = CGImageDestinationCreateWithURL(
                tempJPEGURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                throw ConversionError.conversionFailed
            }

            // 合并原始属性和压缩质量设置
            var finalProperties = imageProperties
            finalProperties[kCGImageDestinationLossyCompressionQuality as String] = 1.0

            CGImageDestinationAddImage(destination, imageRef, finalProperties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw ConversionError.conversionFailed
            }

            // 处理视频数据
            let videoData = try await processVideoForMotionJPEG(from: videoURL)
            print("视频数据大小: \(videoData.count) 字节")
            
            // 添加元数据
            let photoWithMetadata = try await addXiaomiMetadata(to: tempJPEGURL, offset: videoData.count)
            let photoData = try Data(contentsOf: photoWithMetadata)
            print("添加元数据后的照片大小: \(photoData.count) 字节")
            
            // 合并数据
            var finalData = try Data(contentsOf: photoWithMetadata)
            
            // 确保JPEG文件结构完整
            if finalData.count >= 2 && finalData[finalData.count - 2] == 0xFF && finalData[finalData.count - 1] == 0xD9 {
                finalData.removeLast(2)
            }
            
            // 附加视频数据并写入最终文件
            finalData.append(videoData)
            print("最终文件大小: \(finalData.count) 字节")
            try finalData.write(to: outputURL)
            
            return outputURL
        } catch {
            // 如果处理过程中出错，清理所有临时文件
            try? FileManager.default.removeItem(at: tempDirectory)
            throw error
        }
    }
    
    private func separateImageAndVideo(from data: Data, photoURL: URL, videoURL: URL) async throws {
        print("开始分离图片和视频数据...")
        
        // 首先验证文件头是否为JPEG
        guard data.count >= 2 && data[0] == 0xFF && data[1] == 0xD8 else {
            throw ConversionError.invalidInput
        }
        
        // 查找第一个完整的JPEG图像
        var imageEndIndex = 0
        var i = 2
        var segments: [(start: Int, length: Int)] = []
        
        while i < data.count - 1 {
            guard data[i] == 0xFF else {
                i += 1
                continue
            }
            
            let marker = data[i + 1]
            
            // 如果是EOI标记（0xD9），说明找到了JPEG结束
            if marker == 0xD9 {
                imageEndIndex = i + 2
                break
            }
            
            // 如果是SOI标记（0xD8），说明找到了新的JPEG始
            if marker == 0xD8 {
                i += 2
                continue
            }
            
            // 如果是其他段标记
            if marker >= 0xE0 && marker <= 0xEF || // APP segments
               marker == 0xFE || // COM segment
               marker == 0xDB || // DQT segment
               marker == 0xC0 || marker == 0xC2 || // SOF segments
               marker == 0xC4 { // DHT segment
                
                if i + 3 < data.count {
                    let length = Int(data[i + 2]) << 8 | Int(data[i + 3])
                    segments.append((start: i, length: length + 2))
                    i += length + 2
                    continue
                }
            }
            
            i += 1
        }
        
        guard imageEndIndex > 0 else {
            throw ConversionError.invalidInput
        }
        
        // 提取图片数据
        let imageData = data.prefix(imageEndIndex)
        
        // 验证提取的图片数据
        if let image = UIImage(data: imageData) {
            print("验证图片成功，尺寸：\(image.size)")
        } else {
            // 如果直接创建失败，尝试使用CGImageSource
            let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil)
            if let imageSource = imageSource,
               let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                let image = UIImage(cgImage: cgImage)
                print("通过CGImageSource验证图片成功，尺寸：\(image.size)")
            } else {
                throw ConversionError.invalidInput
            }
        }
        
        // 查找视频数据的起始位置
        var videoStartIndex = imageEndIndex
        while videoStartIndex < data.count - 4 {
            // 检查常见的视频文件头
            if data[videoStartIndex..<min(videoStartIndex + 4, data.count)].elementsEqual([0x00, 0x00, 0x00, 0x18]) ||  // MOV
               data[videoStartIndex..<min(videoStartIndex + 4, data.count)].elementsEqual([0x66, 0x74, 0x79, 0x70]) {   // MP4
                break
            }
            videoStartIndex += 1
        }
        
        guard videoStartIndex < data.count - 4 else {
            throw ConversionError.invalidInput
        }
        
        let videoData = data.suffix(from: videoStartIndex)
        
        // 保存分离的数据
        try imageData.write(to: photoURL, options: [.atomic])
        try videoData.write(to: videoURL, options: [.atomic])
    }
    
    private func addXiaomiMetadata(to url: URL, offset: Int) async throws -> URL {
        // 读��原始图片数据
        let imageData = try Data(contentsOf: url)

        // 创建输出 URL
        let outputURL = url.deletingLastPathComponent()
            .appendingPathComponent("MVIMG_\(UUID().uuidString)")
            .appendingPathExtension("jpg")

        // 创建 CGImageSource 来处理图像和元数据
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let imageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            throw ConversionError.conversionFailed
        }

        // 创建目标图像
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL,
                                                              UTType.jpeg.identifier as CFString,
                                                              1, nil) else {
            throw ConversionError.conversionFailed
        }

        // 创建 XMP 元数据
        let xmpString = """
        <?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 5.1.0">
           <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
              <rdf:Description rdf:about=""
                    xmlns:GCamera="http://ns.google.com/photos/1.0/camera/">
                 <GCamera:MicroVideo>1</GCamera:MicroVideo>
                 <GCamera:MicroVideoVersion>1</GCamera:MicroVideoVersion>
                 <GCamera:MicroVideoOffset>\(offset)</GCamera:MicroVideoOffset>
              </rdf:Description>
           </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """

        let xmpIdentifier = "http://ns.adobe.com/xap/1.0/\0"
        guard let xmpIdentifierData = xmpIdentifier.data(using: .utf8) else {
            throw ConversionError.conversionFailed
        }

        let xmpData = xmpString.data(using: .utf8) ?? Data()
        let xmpSegmentLength = xmpIdentifierData.count + xmpData.count + 2

        var xmpSegment = Data([0xFF, 0xE1])
        xmpSegment.append(UInt8(xmpSegmentLength >> 8))
        xmpSegment.append(UInt8(xmpSegmentLength & 0xFF))
        xmpSegment.append(xmpIdentifierData)
        xmpSegment.append(xmpData)

        // 创建 EXIF 段
        var exifData = Data()
        
        // TIFF 头部
        exifData.append(contentsOf: [0x4D, 0x4D]) // 大端字节序 (MM)
        exifData.append(contentsOf: [0x00, 0x2A]) // TIFF 标识符
        
        // IFD0 偏移量
        let ifd0Offset: UInt32 = 8
        exifData.append(contentsOf: [
            UInt8(ifd0Offset >> 24),
            UInt8(ifd0Offset >> 16),
            UInt8(ifd0Offset >> 8),
            UInt8(ifd0Offset)
        ])
        
        // IFD0
        let exifIFDOffset: UInt32 = UInt32(8 + 2 + 12 + 4) // TIFF头部(8) + 条目数量(2) + ExifIFD指针条目(12) + 下一个IFD指针(4)
        
        // IFD0 条目数量
        exifData.append(contentsOf: [0x00, 0x01])
        
        // ExifIFD 指针条目
        exifData.append(contentsOf: [0x87, 0x69]) // Tag 34665
        exifData.append(contentsOf: [0x00, 0x04]) // Type: LONG
        exifData.append(contentsOf: [0x00, 0x00, 0x00, 0x01]) // Count: 1
        exifData.append(contentsOf: [
            UInt8(exifIFDOffset >> 24),
            UInt8(exifIFDOffset >> 16),
            UInt8(exifIFDOffset >> 8),
            UInt8(exifIFDOffset)
        ])
        
        // IFD0 的下一个 IFD 偏移量 (0 表示没有下一个)
        exifData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        
        // ExifIFD
        // ExifIFD 条目数量
        exifData.append(contentsOf: [0x00, 0x01])
        
        // 0x8897 标签条目
        exifData.append(contentsOf: [0x88, 0x97]) // Tag
        exifData.append(contentsOf: [0x00, 0x01]) // Type: BYTE
        exifData.append(contentsOf: [0x00, 0x00, 0x00, 0x01]) // Count: 1
        exifData.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // Value: 1
        
        // ExifIFD 的下一个 IFD 偏移量
        exifData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        
        // 创建完整的 EXIF APP1 段
        var exifSegment = Data()
        exifSegment.append(contentsOf: [0xFF, 0xE1])
        let exifLength = 2 + 6 + exifData.count // 2(长度字段) + 6(Exif\0\0) + TIFF数据长度
        exifSegment.append(contentsOf: [UInt8(exifLength >> 8), UInt8(exifLength & 0xFF)])
        exifSegment.append(contentsOf: "Exif\0\0".data(using: .ascii)!)
        exifSegment.append(exifData)

        // 设置图像和元数据
        CGImageDestinationAddImage(destination, imageRef, metadata as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.conversionFailed
        }

        // 读取生成的图像数据
        var finalData = try Data(contentsOf: outputURL)
        
        // 在 JPEG 头部之后插入 EXIF 和 XMP 段
        if finalData.count >= 2 {
            // 保存 JPEG 头部
            let jpegHeader = finalData.prefix(2)
            finalData.removeFirst(2)
            
            // 重新组装数据
            var newData = Data()
            newData.append(jpegHeader)        // SOI
            newData.append(exifSegment)       // EXIF
            newData.append(xmpSegment)        // XMP（现在放在 EXIF 后面）
            newData.append(finalData)         // 其余 JPEG 数据
            
            try newData.write(to: outputURL)
        }

        return outputURL
    }
} 