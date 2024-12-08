import SwiftUI
import PhotosUI

struct PhotoPickerView: View {
    @ObservedObject var conversionState: ConversionState
    @Binding var showingPhotoPicker: Bool
    @Binding var showingFileImporter: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            if conversionState.selectedPhotos.isEmpty {
                ContentUnavailableView {
                    Label("没有选择照片", systemImage: "photo.on.rectangle")
                } description: {
                    Text("点击下方按钮从相册选择照片")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100), spacing: 10)
                    ], spacing: 10) {
                        ForEach(Array(conversionState.selectedPhotos.enumerated()), id: \.offset) { index, photo in
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) {
                                    Button(action: {
                                        deletePhoto(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .red)
                                            .background(Color.black.opacity(0.3))
                                            .clipShape(Circle())
                                    }
                                    .padding(4)
                                }
                                .shadow(radius: 2)
                        }
                    }
                    .padding()
                }
            }
            
            HStack(spacing: 16) {
                Button(action: {
                    showingPhotoPicker = true
                }) {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                
                Button(action: {
                    showingFileImporter = true
                }) {
                    Label("从文件选择", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
            .padding(.horizontal)
        }
    }
    
    private func deletePhoto(at index: Int) {
        guard index < conversionState.selectedPhotos.count else { return }
        conversionState.selectedPhotos.remove(at: index)
        if index < conversionState.selectedURLs.count {
            // 删除临时文件
            try? FileManager.default.removeItem(at: conversionState.selectedURLs[index])
            conversionState.selectedURLs.remove(at: index)
        }
        if index < conversionState.selectedItems.count {
            conversionState.selectedItems.remove(at: index)
        }
    }
} 