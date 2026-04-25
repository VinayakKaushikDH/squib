import AppKit
import SwiftUI
import SquibCore
import SquibUI

@main
@MainActor
struct SnapshotTool {
    static func main() throws {
        // Parse arguments: --all, --id <name>, --out <path>, --fixtures <path>
        var renderAll = false
        var filterID: String? = nil
        var outDir = URL(fileURLWithPath: "Tests/Snapshots/output")
        var fixturesDir = URL(fileURLWithPath: "Tests/Snapshots/fixtures")

        let args = CommandLine.arguments.dropFirst()
        var i = args.startIndex
        while i < args.endIndex {
            switch args[i] {
            case "--all":
                renderAll = true
            case "--id":
                args.formIndex(after: &i)
                if i < args.endIndex { filterID = args[i] }
            case "--out":
                args.formIndex(after: &i)
                if i < args.endIndex { outDir = URL(fileURLWithPath: args[i]) }
            case "--fixtures":
                args.formIndex(after: &i)
                if i < args.endIndex { fixturesDir = URL(fileURLWithPath: args[i]) }
            default: break
            }
            args.formIndex(after: &i)
        }

        if !renderAll && filterID == nil {
            print("usage: bubbleSnapshotTool --all | --id <name> [--out <dir>] [--fixtures <dir>]")
            exit(1)
        }

        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let fixtures = try loadFixtures(from: fixturesDir, id: filterID)
        guard !fixtures.isEmpty else {
            print("No fixtures found" + (filterID.map { " matching id '\($0)'" } ?? ""))
            exit(1)
        }

        for fixture in fixtures {
            let request = fixture.toPermissionRequest()
            let vm = BubbleViewModel(request: request)
            let width: CGFloat = request.isElicitation ? 380 : 340
            let card = BubbleCardView(model: vm, _renderImmediately: true)
                .frame(width: width)
                .background(Color(white: 0.10))
                .preferredColorScheme(.dark)

            let renderer = ImageRenderer(content: card)
            renderer.scale = 2.0

            guard let nsImage = renderer.nsImage else {
                print("  FAIL: ImageRenderer returned nil for '\(fixture.id)'")
                continue
            }

            let outURL = outDir.appending(path: "\(fixture.id).png")
            guard let tiff = nsImage.tiffRepresentation,
                  let rep  = NSBitmapImageRep(data: tiff),
                  let png  = rep.representation(using: .png, properties: [:]) else {
                print("  FAIL: PNG conversion failed for '\(fixture.id)'")
                continue
            }
            try png.write(to: outURL)
            print("  \(fixture.id) → \(outURL.path(percentEncoded: false))")
        }
    }
}
