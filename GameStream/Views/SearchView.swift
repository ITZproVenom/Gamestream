import SwiftUI

struct SearchView: View {
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            AnimatedBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Search")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Find your next game")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.top, 12)

                    // Search field
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))

                        TextField(
                            "Search games",
                            text: $searchText
                        )
                        .focused($searchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.white)
                        .font(.system(size: 17, weight: .medium))

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 58)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                        .strokeBorder(
                            .white.opacity(searchFocused ? 0.3 : 0.12),
                            lineWidth: 1
                        )
                    }
                    .shadow(
                        color: .black.opacity(0.15),
                        radius: 20,
                        y: 10
                    )
                    .animation(
                        .easeInOut(duration: 0.2),
                        value: searchFocused
                    )

                    // Empty state
                    if searchText.isEmpty {
                        VStack(spacing: 18) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 42, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))

                            VStack(spacing: 6) {
                                Text("What are you playing?")
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)

                                Text("Search for games available on Xbox Cloud Gaming.")
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 70)
                    } else {
                        // Search action
                        Button {
                            openXboxSearch()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")

                                Text("Search Xbox Cloud Gaming")
                                    .font(.headline)

                                Spacer()

                                Image(systemName: "arrow.up.right")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 58)
                            .background(
                                .ultraThinMaterial,
                                in: RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                                .strokeBorder(
                                    .white.opacity(0.15),
                                    lineWidth: 1
                                )
                            }
                        }
                        .buttonStyle(.plain)

                        Text("Results")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(.top, 8)

                        Text("Xbox's search results will open here.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func openXboxSearch() {
        guard let encoded = searchText
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(
                string: "https://www.xbox.com/en-IN/play#search?query=\(encoded)"
              )
        else {
            return
        }

        searchFocused = false

        // Open the Xbox search page in the existing streaming web view.
        NotificationCenter.default.post(
            name: .openXboxSearch,
            object: url
        )
    }
}

extension Notification.Name {
    static let openXboxSearch = Notification.Name("openXboxSearch")
}