//
//  ContentView.swift
//  MotionJPEGConvert
//
//  Created by 李龙宇 on 2024/12/3.
//

import SwiftUI
import PhotosUI
import Photos

struct ContentView: View {
    @EnvironmentObject private var permissionManager: PermissionManager
    @StateObject private var conversionState = ConversionState()
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingShareSheet = false
    @State private var convertedFileURL: URL?
    
    var body: some View {
        NavigationView {
            Group {
                if permissionManager.photoLibraryPermissionStatus == .notDetermined {
                    PermissionRequestView()
                } else if permissionManager.photoLibraryPermissionStatus == .denied {
                    PermissionDeniedView()
                } else {
                    VStack(spacing: 20) {
                        Picker("转换模式", selection: $conversionState.convertMode) {
                            Text(ConvertMode.motionJPEGToLive.title).tag(ConvertMode.motionJPEGToLive)
                            Text(ConvertMode.liveToMotionJPEG.title).tag(ConvertMode.liveToMotionJPEG)
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        .onChange(of: conversionState.convertMode) { oldValue, newValue in
                            conversionState.reset()
                        }
                        
                        PhotoPickerView(
                            conversionState: conversionState,
                            showingPhotoPicker: $showingPhotoPicker,
                            showingFileImporter: $showingFileImporter
                        )
                        
                        if conversionState.isConverting {
                            ProgressView(value: conversionState.conversionProgress) {
                                Text("转换中... \(Int(conversionState.conversionProgress * 100))%")
                            }
                            .padding()
                        }
                        
                        Button(action: {
                            Task {
                                await convertPhotos()
                            }
                        }) {
                            Label("开始转换", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                        .disabled(conversionState.selectedPhotos.isEmpty || conversionState.isConverting)
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("照片转换器")
            .alert("提示", isPresented: $showingAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = convertedFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $conversionState.selectedItems,
                maxSelectionCount: 10,
                matching: conversionState.convertMode == .motionJPEGToLive ? .images : .livePhotos
            )
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                Task {
                    await handleFileImport(result)
                }
            }
            .onChange(of: conversionState.selectedItems) { oldValue, newValue in
                Task {
                    await loadTransferables()
                }
            }
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            await loadFiles(from: urls)
        case .failure(let error):
            showingAlert = true
            alertMessage = "导入文件失败：\(error.localizedDescription)"
        }
    }
    
    private func loadFiles(from urls: [URL]) async {
        conversionState.selectedPhotos.removeAll()
        conversionState.selectedURLs.removeAll()
        
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { continue }
            
            conversionState.selectedPhotos.append(image)
            conversionState.selectedURLs.append(url)
        }
    }
    
    private func loadTransferables() async {
        // 检查权限
        if permissionManager.photoLibraryPermissionStatus != .authorized {
            await withCheckedContinuation { continuation in
                permissionManager.requestPhotoLibraryPermission { granted in
                    if !granted {
                        showingAlert = true
                        alertMessage = "需要相册访问权限才能继续操作。请在设置中允许访问相册。"
                        conversionState.selectedItems.removeAll()
                    }
                    continuation.resume()
                }
            }
            return
        }
        
        conversionState.selectedPhotos.removeAll()
        conversionState.selectedURLs.removeAll()
        
        for (index, item) in conversionState.selectedItems.enumerated() {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    conversionState.selectedPhotos.append(image)
                    
                    // 创建临时文件
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("jpg")
                    try data.write(to: tempURL)
                    conversionState.selectedURLs.append(tempURL)
                    
                    // 更新进度
                    conversionState.conversionProgress = Double(index + 1) / Double(conversionState.selectedItems.count)
                }
            } catch {
                print("加载第 \(index + 1) 张图片失败：\(error.localizedDescription)")
            }
        }
        
        if conversionState.selectedPhotos.isEmpty {
            showingAlert = true
            alertMessage = "没有成功导入任何图片，请重试。"
        }
    }
    
    private func convertPhotos() async {
        conversionState.isConverting = true
        conversionState.conversionProgress = 0
        
        do {
            switch conversionState.convertMode {
            case .motionJPEGToLive:
                if let url = conversionState.selectedURLs.first {
                    try await MotionJPEGToLiveConverter.shared.convert(from: url)
                    showingAlert = true
                    alertMessage = "转换成功！Live Photo 已保存到相册。"
                }
            case .liveToMotionJPEG:
                if let item = conversionState.selectedItems.first {
                    let processedURL = try await LiveToMotionJPEGConverter.shared.convert(from: item)
                    convertedFileURL = processedURL
                    showingShareSheet = true
                }
            }
        } catch let error as NSError {
            showingAlert = true
            
            if error.domain == "PHPhotosErrorDomain" {
                switch error.code {
                case -1:
                    alertMessage = "保存失败。请尝试以下步骤：\n1. 删除应用重新安装\n2. 在设置中关闭相册权限再重新打开\n3. 重启设备后重试"
                case 3300:
                    alertMessage = "无法保存到相册，请检查存储空间是否充足"
                default:
                    alertMessage = "保存到相册失败：\(error.localizedDescription)"
                }
            } else {
                alertMessage = "转换失败：\(error.localizedDescription)"
            }
        }
        
        conversionState.isConverting = false
        conversionState.conversionProgress = 1.0
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDevice("iPhone 14 Pro")
            .environmentObject(PermissionManager())
    }
}
