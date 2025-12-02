import SwiftUI


struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        ZStack {
            Group {
                if authManager.isAuthenticated {
                    MainTabView()
                } else if authManager.needsProfileCompletion {
                    ProfileCompletionView(isAppleSignUp: true)
                } else {
                    SignInView()
                }
            }
        }
        // IMPORTANT: remove any other .onTapGesture { hideKeyboard() } you added globally
        .background(InstallGlobalTapToDismissKeyboard())
        .withToast()  // ✅ Add toast at root level
        // NOTE: Profile navigation is handled by .withProfileNavigationDestination() in individual views
        // Do NOT use .withProfileNavigation() here - that's the old overlay approach
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: authManager.needsProfileCompletion)
        .task {
            // ✅ CHECK FOR EXISTING SESSION ON APP LAUNCH
            await authManager.checkExistingSession()
        }
    }
}

/// Reusable translucent bar-style background (matches TabView/UITabBar feel).
extension View {
    func barTranslucentBackground() -> some View {
        self
            .background(.bar)                 // adaptive blur/tint like system bars
            .overlay(Divider(), alignment: .bottom) // subtle hairline like bars
    }
}

#Preview {
    ContentView()
}
