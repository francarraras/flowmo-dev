import SwiftUI

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

/// Loads a loose package resource explicitly. Named-image lookup expects an
/// asset catalog on some hosts, while the command-line build ships this PNG.
@MainActor
enum HorizonArtwork {
    static let image: Image = {
        let url = Bundle.module.url(forResource: "HorizonStudy", withExtension: "png")
        #if os(macOS)
            if let url, let source = NSImage(contentsOf: url) {
                return Image(nsImage: source)
            }
        #elseif os(iOS)
            if let url, let source = UIImage(contentsOfFile: url.path) {
                return Image(uiImage: source)
            }
        #endif
        return Image(systemName: "sun.horizon")
    }()
}
