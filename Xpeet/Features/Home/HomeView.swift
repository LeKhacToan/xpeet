import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text(viewModel.message)
                    .font(.title2.bold())

                Button("Tap me", action: viewModel.increment)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Home")
        }
    }
}

#Preview {
    HomeView()
}
