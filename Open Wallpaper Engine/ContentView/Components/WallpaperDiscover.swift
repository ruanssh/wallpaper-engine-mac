//
//  WallpaperDiscover.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/21.
//

import SwiftUI

struct WallpaperDiscover: SubviewOfContentView {
    @ObservedObject var viewModel: ContentViewModel
    @StateObject private var discoverViewModel = WallpaperDiscoverViewModel()

    init(contentViewModel viewModel: ContentViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Discover")
                        .font(.title2)
                        .bold()
                    Text("Browse and import from MoeWalls")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if discoverViewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task {
                        await discoverViewModel.reload()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            if let errorMessage = discoverViewModel.errorMessage, discoverViewModel.items.isEmpty {
                VStack(spacing: 8) {
                    Text("Failed to load wallpapers")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Button("Try Again") {
                        Task {
                            await discoverViewModel.reload()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        ForEach(discoverViewModel.items) { item in
                            MoeWallsCard(item: item,
                                         isImporting: discoverViewModel.importingIDs.contains(item.id)) {
                                Task {
                                    await discoverViewModel.importWallpaper(item)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if let importMessage = discoverViewModel.importMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(importMessage)
                        .font(.caption)
                    Spacer()
                }
            } else if let importError = discoverViewModel.importError {
                HStack {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(importError)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                }
            }
        }
        .task {
            await discoverViewModel.loadIfNeeded()
        }
    }
}

private struct MoeWallsCard: View {
    let item: MoeWallsWallpaper
    let isImporting: Bool
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: item.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Color.secondary.opacity(0.15)
                        .overlay(Image(systemName: "photo"))
                case .empty:
                    Color.secondary.opacity(0.15)
                        .overlay(ProgressView())
                @unknown default:
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(height: 140)
            .clipped()
            .overlay {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        if let category = item.category {
                            Text(category)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.thinMaterial, in: Capsule())
                        }
                        if let resolution = item.resolution {
                            Text(resolution)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.thinMaterial, in: Capsule())
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }

            Text(item.title)
                .font(.headline)
                .lineLimit(2)

            HStack {
                Link(destination: item.postURL) {
                    Label("Open", systemImage: "safari")
                }
                .buttonStyle(.link)

                Spacer()

                Button {
                    onImport()
                } label: {
                    if isImporting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Importing")
                        }
                    } else {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MoeWallsWallpaper: Identifiable {
    let id: Int
    let title: String
    let postURL: URL
    let thumbnailURL: URL?
    let category: String?
    let resolution: String?
}

@MainActor
private final class WallpaperDiscoverViewModel: ObservableObject {
    @Published private(set) var items = [MoeWallsWallpaper]()
    @Published private(set) var isLoading = false
    @Published private(set) var importingIDs = Set<Int>()
    @Published var errorMessage: String?
    @Published var importError: String?
    @Published var importMessage: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func loadIfNeeded() async {
        guard items.isEmpty else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil

        do {
            let request = requestFor(urlString: "https://moewalls.com/wp-json/wp/v2/posts?per_page=30&page=1&_embed=wp:featuredmedia")
            let (data, _) = try await session.data(for: request)
            let decoded = try JSONDecoder().decode([MoeWallsPostDTO].self, from: data)

            items = decoded.compactMap { post in
                guard let postURL = URL(string: post.link) else { return nil }
                let category = post.categories?.first.flatMap { categoryNameByID[$0] }
                let resolution = post.resolutions?.first.flatMap { resolutionNameByID[$0] }
                let title = post.title.rendered
                    .strippingHTML()
                    .replacingOccurrences(of: " Live Wallpaper", with: "")
                let thumbnailURL = post.embedded?.featuredMedia?.first?.sourceURL.flatMap(URL.init)
                return MoeWallsWallpaper(id: post.id,
                                         title: title,
                                         postURL: postURL,
                                         thumbnailURL: thumbnailURL,
                                         category: category,
                                         resolution: resolution)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func importWallpaper(_ item: MoeWallsWallpaper) async {
        guard !importingIDs.contains(item.id) else { return }
        importingIDs.insert(item.id)
        importError = nil
        importMessage = nil

        defer {
            importingIDs.remove(item.id)
        }

        do {
            let remoteURL = try await resolveDownloadURL(for: item.postURL)
            let downloadRequest = requestFor(url: remoteURL)
            let (tempURL, _) = try await session.download(for: downloadRequest)

            let stagedURL = FileManager.default.temporaryDirectory
                .appending(path: "\(UUID().uuidString).mp4")
            try? FileManager.default.removeItem(at: stagedURL)
            try FileManager.default.copyItem(at: tempURL, to: stagedURL)

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                AppDelegate.shared.importVideoFile(url: stagedURL, suggestedTitle: item.title) { result in
                    try? FileManager.default.removeItem(at: stagedURL)
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }

            importMessage = "Imported \(item.title)"
        } catch {
            importError = "Failed to import \(item.title): \(error.localizedDescription)"
        }
    }

    private func resolveDownloadURL(for pageURL: URL) async throws -> URL {
        let request = requestFor(url: pageURL)
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw DiscoverError.cannotReadPage
        }

        guard let token = html.downloadToken else {
            throw DiscoverError.downloadTokenMissing
        }

        guard let url = URL(string: "https://go.moewalls.com/download.php?video=\(token)") else {
            throw DiscoverError.invalidDownloadURL
        }
        return url
    }

    private func requestFor(urlString: String) -> URLRequest {
        requestFor(url: URL(string: urlString)!)
    }

    private func requestFor(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}

private enum DiscoverError: LocalizedError {
    case cannotReadPage
    case downloadTokenMissing
    case invalidDownloadURL

    var errorDescription: String? {
        switch self {
        case .cannotReadPage:
            return "Cannot read wallpaper page"
        case .downloadTokenMissing:
            return "Download token not found"
        case .invalidDownloadURL:
            return "Invalid download URL"
        }
    }
}

private struct MoeWallsPostDTO: Decodable {
    struct TitleDTO: Decodable {
        let rendered: String
    }

    struct EmbeddedDTO: Decodable {
        struct FeaturedMediaDTO: Decodable {
            let sourceURL: String?

            enum CodingKeys: String, CodingKey {
                case sourceURL = "source_url"
            }
        }

        let featuredMedia: [FeaturedMediaDTO]?

        enum CodingKeys: String, CodingKey {
            case featuredMedia = "wp:featuredmedia"
        }
    }

    let id: Int
    let link: String
    let title: TitleDTO
    let categories: [Int]?
    let resolutions: [Int]?
    let embedded: EmbeddedDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case link
        case title
        case categories
        case resolutions
        case embedded = "_embedded"
    }
}

private extension String {
    func strippingHTML() -> String {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        if let data = data(using: .utf8),
           let attributed = try? NSAttributedString(data: data,
                                                    options: options,
                                                    documentAttributes: nil) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var downloadToken: String? {
        let patterns = [
            #"id=[\"']moe-download[\"'][^>]*data-url=[\"']([^\"']+)[\"']"#,
            #"data-url=[\"']([^\"']+)[\"'][^>]*id=[\"']moe-download[\"']"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(startIndex..<endIndex, in: self)
            guard let match = regex.firstMatch(in: self, options: [], range: range),
                  let tokenRange = Range(match.range(at: 1), in: self)
            else {
                continue
            }
            return String(self[tokenRange])
        }

        return nil
    }
}

private let categoryNameByID: [Int: String] = [
    1: "Abstract",
    17: "Animal",
    18: "Anime",
    19: "Fantasy",
    20: "Games",
    21: "Landscape",
    22: "Lifestyle",
    23: "Movies",
    24: "Others",
    25: "Pixel Art",
    26: "Sci-fi",
    27: "Vehicle"
]

private let resolutionNameByID: [Int: String] = [
    33: "1920x1080",
    139: "1280x720",
    142: "3440x1440",
    192: "3840x2160",
    310: "2560x1440",
    500: "2560x1600",
    759: "2560x1080",
    818: "1366x768",
    1175: "2560x1700",
    5210: "7680x2160",
    5781: "3840x2400",
    7085: "5120x1440"
]

struct WallpaperDiscover_Previews: PreviewProvider {
    static var previews: some View {
        WallpaperDiscover(contentViewModel: ContentViewModel(isStaging: true, topTabBarSelection: 1))
    }
}
