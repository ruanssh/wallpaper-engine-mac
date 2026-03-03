//
//  ImportPanels.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/4.
//

import Cocoa
import AVKit
import UniformTypeIdentifiers

struct WPImportError: LocalizedError {
    var errorDescription: String?
    var failureReason: String?
    var helpAnchor: String?
    var recoverySuggestion: String?
    
    static let permissionDenied         = WPImportError(errorDescription: "Permission Denied",
                                                failureReason: "This app doesn't have the permission to access to the folder(s) you selected",
                                                helpAnchor: "File Permission",
                                                recoverySuggestion: "Try enable it in 'System Settings' - 'Privacy & Security'")
    
    static let doesNotContainWallpaper  = WPImportError(errorDescription: "No Wallpaper(s) Inside",
                                                       failureReason: "Maybe you selected the wrong folder which doesn't contain any wallpapers",
                                                       helpAnchor: "Contents in Folder(s)",
                                                       recoverySuggestion: "Check the folder(s) you selected and try again")
    
    static let unkown                   = WPImportError(errorDescription: "Unkown Error",
                                                        failureReason: "",
                                                        helpAnchor: "",
                                                        recoverySuggestion: "")
}

extension AppDelegate {
    private func sanitizedWallpaperName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Wallpaper" : cleaned
    }

    private func uniqueWallpaperDirectory(for baseName: String, in directory: URL) -> URL {
        var candidate = directory.appending(path: baseName)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(baseName)-\(index)")
            index += 1
        }
        return candidate
    }

    @objc func openImportFromFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .folder]
        panel.message = String(localized: "Select a wallpaper folder (with project.json) or a video file (.mp4, .mov)")
        panel.beginSheetModal(for: self.mainWindowController.window) { [weak self] response in
            if response != .OK { return }
            guard let url = panel.urls.first else { return }

            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

            if isDirectory.boolValue {
                self?.importWallpaperFolder(url: url)
            } else {
                self?.importVideoFile(url: url)
            }
        }
    }

    private func importWallpaperFolder(url: URL) {
        guard let wallpaperFolder = try? FileWrapper(url: url) else {
            DispatchQueue.main.async {
                self.contentViewModel.alertImportModal(which: .permissionDenied)
            }
            return
        }

        guard wallpaperFolder.fileWrappers?["project.json"] != nil else {
            DispatchQueue.main.async {
                self.contentViewModel.alertImportModal(which: .doesNotContainWallpaper)
            }
            return
        }

        DispatchQueue.main.async {
            do {
                try FileManager.default.copyItem(
                    at: url,
                    to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appending(path: url.lastPathComponent)
                )
                self.contentViewModel.refresh()
            } catch {
                print("Import error: \(error)")
                self.contentViewModel.alertImportModal(which: .unkown)
            }
        }
    }

    func importVideoFile(url: URL,
                         suggestedTitle: String? = nil,
                         completion: ((Result<Void, Error>) -> Void)? = nil) {
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let trimmedSuggestedTitle = suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = (trimmedSuggestedTitle?.isEmpty == false ? trimmedSuggestedTitle : nil) ?? fallbackName
        let name = sanitizedWallpaperName(rawName)
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let filename = "\(name).\(ext)"
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let wallpaperDir = uniqueWallpaperDirectory(for: name, in: documentsDir)

        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        let time = CMTimeMake(value: 1, timescale: 1)

        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] _, cgImage, _, _, _ in
            DispatchQueue.main.async {
                do {
                    try FileManager.default.createDirectory(at: wallpaperDir, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: wallpaperDir.appending(path: filename))

                    let project = WEProject(file: filename, preview: "preview.jpg", title: name, type: "video")
                    let projectData = try JSONEncoder().encode(project)
                    try projectData.write(to: wallpaperDir.appending(path: "project.json"))

                    if let cgImage = cgImage {
                        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                        if let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) {
                            try jpegData.write(to: wallpaperDir.appending(path: "preview.jpg"))
                        }
                    }

                    self?.contentViewModel.refresh()
                    completion?(.success(()))
                } catch {
                    print("Import video error: \(error)")
                    try? FileManager.default.removeItem(at: wallpaperDir)
                    self?.contentViewModel.alertImportModal(which: .unkown)
                    completion?(.failure(error))
                }
            }
        }
    }
    
    @objc func openImportFromFoldersPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: self.mainWindowController.window) { response in
            if response != .OK { return }
            print(String(describing: panel.urls))
            
            DispatchQueue.main.async {
                self.contentViewModel.wallpaperUrls.append(contentsOf: panel.urls)
            }
        }
    }
}
