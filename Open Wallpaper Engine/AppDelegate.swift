//
//  AppDelegate.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/6/6.
//

import Cocoa
import SwiftUI
import AVKit
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow!
    
    var mainWindowController: MainWindowController!
    
    var wallpaperWindow: NSWindow!
    
    var contentViewModel = ContentViewModel()
    var wallpaperViewModel = WallpaperViewModel()
    var globalSettingsViewModel = GlobalSettingsViewModel()
    
    var importOpenPanel: NSOpenPanel!
    
    var eventHandler: Any?
    var spaceObserver: Any?
    var lastStaticWallpaperUrl: URL?
    
    static var shared = AppDelegate()
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 创建设置视窗
        setSettingsWindow()
        
        // 创建桌面壁纸视窗
        setWallpaperWindow()
        
        // 创建化左上角菜单栏
        setMainMenu()
        
        // 创建化右上角常驻菜单栏
        setStatusMenu()
        
        // 创建主视窗
        self.mainWindowController = MainWindowController()
        
        // 将外部输入传递到壁纸窗口
        AppDelegate.shared.setEventHandler()

        // Aplica wallpaper estático ao trocar de Space
        self.spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reapplyStaticWallpaper()
        }
    }
    
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let dockMenu = self.statusItem.menu?.copy() as! NSMenu?
        dockMenu?.items.removeLast() // Remove `Quit` menu item
        return dockMenu
    }
    
// MARK: - delegate methods
    func applicationDidFinishLaunching(_ notification: Notification) {
        saveCurrentWallpaper()
        AppDelegate.shared.setPlacehoderWallpaper(with: wallpaperViewModel.currentWallpaper)
        
        // 显示桌面壁纸
        self.wallpaperWindow.orderFront(nil)
        
        if globalSettingsViewModel.isFirstLaunch {
            self.mainWindowController.window.center()
            self.mainWindowController.window.makeKeyAndOrderFront(nil)
        }
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !self.mainWindowController.window.isVisible && !settingsWindow.isVisible {
            self.mainWindowController.window?.makeKeyAndOrderFront(nil)
        }
        
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let wallpaper = UserDefaults.standard.url(forKey: "OSWallpaper") {
            try? NSWorkspace.shared.setDesktopImageURL(wallpaper, for: .main!)
        }
        
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        do {
            let filesURL = try FileManager.default.contentsOfDirectory(at: cacheDirectory,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: .skipsHiddenFiles)
            for url in filesURL {
                if url.lastPathComponent.contains("staticWP") {
                    try FileManager.default.removeItem(at: url)
                }
            }
        } catch {
            print(error)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

// MARK: - misc methods
    @objc func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow.center()
        self.settingsWindow.makeKeyAndOrderFront(nil)
    }
    
    @objc func openMainWindow() {
        self.mainWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @MainActor @objc func toggleFilter() {
        self.contentViewModel.isFilterReveal.toggle()
    }
    
// MARK: Set Settings Window
    func setSettingsWindow() {
        self.settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        self.settingsWindow.title = "Settings"
        self.settingsWindow.isReleasedWhenClosed = false
        self.settingsWindow.toolbarStyle = .preference
        
        self.settingsWindow.delegate = self
        
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        
        toolbar.selectedItemIdentifier = SettingsToolbarIdentifiers.performance
        
        self.settingsWindow.toolbar = toolbar
        self.settingsWindow.contentView = NSHostingView(rootView: SettingsView().environmentObject(self.globalSettingsViewModel))
    }
    
// MARK: Set Wallpaper Window - Most efforts
    func setWallpaperWindow() {
        self.wallpaperWindow = NSWindow()
        
        self.wallpaperWindow.styleMask = [.borderless, .fullSizeContentView]
        self.wallpaperWindow.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
        self.wallpaperWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]

        self.wallpaperWindow.setFrame(NSScreen.main!.frame, display: true)
        self.wallpaperWindow.isMovable = false
        self.wallpaperWindow.titlebarAppearsTransparent = true
        self.wallpaperWindow.titleVisibility = .hidden
        self.wallpaperWindow.canHide = false
        self.wallpaperWindow.canBecomeVisibleWithoutLogin = true
        self.wallpaperWindow.isReleasedWhenClosed = false
        
        self.wallpaperWindow.contentView = NSHostingView(rootView:
            WallpaperView(viewModel: self.wallpaperViewModel)
        )
    }
    
    func windowWillClose(_ notification: Notification) {
        globalSettingsViewModel.reset()
    }
    
    func setEventHandler() {
        self.eventHandler = NSEvent.addGlobalMonitorForEvents(matching: .any) { [weak self] event in
            // contentView.subviews.first -> SwiftUIView.subviews.first -> WKWebView
            if let webview = self?.wallpaperWindow.contentView?.subviews.first?.subviews.first,
               let frontmostApplication = NSWorkspace.shared.frontmostApplication,
                   webview is WKWebView,
                   frontmostApplication.bundleIdentifier == "com.apple.finder" {
                switch event.type {
                case .scrollWheel:
                    webview.scrollWheel(with: event)
                case .mouseMoved:
                    webview.mouseMoved(with: event)
                case .mouseEntered:
                    webview.mouseEntered(with: event)
                case .mouseExited:
                    webview.mouseExited(with: event)

                case .leftMouseUp:
                    fallthrough
                case .rightMouseUp:
                    webview.mouseUp(with: event)
                    
                case .leftMouseDown:
                    webview.mouseDown(with: event)
    //            case .rightMouseDown:
    //                view?.mouseDown(with: event)
                    
                case .leftMouseDragged:
                    fallthrough
                case .rightMouseDragged:
                    webview.mouseDragged(with: event)
                    
                default:
                    break
                }
            }
        }
    }
    
    func saveCurrentWallpaper() {
        var wallpaper: URL {
            var osWallpaper: URL { NSWorkspace.shared.desktopImageURL(for: .main!)! }
            if let wallpaper = UserDefaults.standard.url(forKey: "OSWallpaper") {
                if wallpaper != osWallpaper {
                    if !wallpaper.lastPathComponent.contains("staticWP") {
                        return wallpaper
                    }
                }
            }
            return osWallpaper
        }
        UserDefaults.standard.set(wallpaper, forKey: "OSWallpaper")
    }
    
    func setPlacehoderWallpaper(with wallpaper: WEWallpaper) {
        switch wallpaper.project.type.lowercased() {
        case "video":
            self.lastStaticWallpaperUrl = nil
            return
        case "web", "scene":
            guard self.globalSettingsViewModel.settings.adjustMenuBarTint else { return }

            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let cacheUrl = cacheDir.appending(path: "staticWP_\(wallpaper.wallpaperDirectory.hashValue).tiff")
            let previewPath = wallpaper.wallpaperDirectory.appending(component: wallpaper.project.preview)
            if let image = NSImage(contentsOf: previewPath), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                applyStaticWallpaper(cgImage: cgImage, cacheUrl: cacheUrl)
            }
        default:
            return
        }
    }

    private func applyStaticWallpaper(cgImage: CGImage, cacheUrl: URL) {
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        guard let data = nsImage.tiffRepresentation else { return }
        do {
            try data.write(to: cacheUrl, options: .atomic)
            self.lastStaticWallpaperUrl = cacheUrl
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(cacheUrl, for: screen)
            }
        } catch {
            print("Failed to set static wallpaper: \(error)")
        }
    }

    private func reapplyStaticWallpaper() {
        guard self.globalSettingsViewModel.settings.adjustMenuBarTint else { return }
        guard let url = lastStaticWallpaperUrl else { return }
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen)
        }
    }
}

enum SettingsToolbarIdentifiers {
    static let performance = NSToolbarItem.Identifier(rawValue: "performance")
    static let general = NSToolbarItem.Identifier(rawValue: "general")
    static let plugins = NSToolbarItem.Identifier(rawValue: "plugins")
    static let about = NSToolbarItem.Identifier(rawValue: "about")
}
