//
//  ExplorerBottomBar.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/15.
//

import SwiftUI

struct ExplorerBottomBar: View {
    var body: some View {
        VStack {
            HStack {
                Text("Playlist").font(.largeTitle)
                HStack(spacing: 2) {
                    Button { } label: {
                        Label("Load", systemImage: "folder.fill")
                    }
                    .disabled(true)
                    Button { } label: {
                        Label("Save", systemImage: "square.and.arrow.down.fill")
                    }
                    .disabled(true)
                    Button { } label: {
                        Label("Configure", systemImage: "gearshape.2.fill")
                    }
                    .disabled(true)
                    Button {
                        AppDelegate.shared.openImportFromFolderPanel()
                    } label: {
                        Label("Add Wallpaper", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            HStack {
                Button { } label: {
                    Label("Wallpaper Editor", systemImage: "pencil.and.ruler.fill")
                        .frame(width: 220)
                }
                .buttonStyle(.borderedProminent)
                .disabled(true)
                Button {
                    AppDelegate.shared.openImportFromFolderPanel()
                } label: {
                    Label("Open Wallpaper", systemImage: "arrow.up.bin.fill")
                        .frame(width: 220)
                }
                Spacer()
            }
        }    }
}
