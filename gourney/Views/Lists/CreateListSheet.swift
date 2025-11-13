import SwiftUI

struct CreateListSheet: View {
    @ObservedObject var viewModel: ListsViewModel
    @Binding var isPresented: Bool
    
    @State private var title = ""
    @State private var isCreating = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 50
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isCreating {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("New List")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Input
                VStack(alignment: .leading, spacing: 6) {
                    TextField("List name", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isFocused)
                        .disabled(isCreating)
                        .submitLabel(.done)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onSubmit {
                            if isValid {
                                createList()
                            }
                        }
                    
                    HStack {
                        Spacer()
                        Text("\(title.count)/50")
                            .font(.system(size: 11))
                            .foregroundColor(title.count > 50 ? Color(red: 1.0, green: 0.4, blue: 0.4) : .secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                
                // Buttons
                HStack(spacing: 10) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6))
                    .clipShape(Capsule())
                    .disabled(isCreating)
                    
                    Button {
                        createList()
                    } label: {
                        if isCreating {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 44)
                    .background(
                        isValid ?
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            colors: [Color.gray, Color.gray],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: isValid ? Color.black.opacity(0.1) : Color.clear, radius: 3, y: 1)
                    .disabled(!isValid || isCreating)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(width: 320)
            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.25), radius: 15, y: 8)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
    }
    
    private func createList() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            isCreating = true
            let success = await viewModel.createList(
                title: trimmedTitle,
                description: nil,
                visibility: "private"
            )
            isCreating = false
            
            if success {
                isPresented = false
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray
        CreateListSheet(viewModel: ListsViewModel(), isPresented: .constant(true))
    }
}
