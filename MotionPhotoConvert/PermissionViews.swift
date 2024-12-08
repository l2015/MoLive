import SwiftUI

struct PermissionRequestView: View {
    @EnvironmentObject private var permissionManager: PermissionManager
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("需要访问照片库权限")
                .font(.headline)
            
            Text("我们需要访问您的照片库来选择和保存照片")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("授权访问") {
                permissionManager.requestPhotoLibraryPermission { granted in
                    if !granted {
                        showingAlert = true
                        alertMessage = "需要相册访问权限才能继续操作。请在设置中允许访问相册。"
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .alert("提示", isPresented: $showingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.yellow)
            
            Text("需要照片库访问权限")
                .font(.headline)
            
            Text("请在设置中允许访问照片库，以便选择和保存照片")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("打开设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
} 