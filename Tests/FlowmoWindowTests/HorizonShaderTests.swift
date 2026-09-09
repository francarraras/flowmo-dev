import Metal
import XCTest

@testable import FlowmoLook

/// The horizon shader ships as source and compiles at first use, so a typo
/// would only surface as a silently missing canvas. Compile it here instead.
@MainActor
final class HorizonShaderTests: XCTestCase {
    func testEmbeddedShaderSourceCompilesWhereMetalExists() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device on this machine; the backdrop falls back to the bundled artwork.")
        }
        let library = try device.makeLibrary(source: HorizonShaderSource.source, options: nil)
        XCTAssertNotNil(library.makeFunction(name: "horizonVertex"))
        XCTAssertNotNil(library.makeFunction(name: "horizonFragment"))
        XCTAssertTrue(HorizonRenderer.isAvailable)
    }

    func testUniformLayoutMatchesShaderStruct() {
        // A float2 followed by fifteen scalars, packed exactly as Metal lays out
        // the same struct: 8 + 15 × 4 bytes, padded to float2 alignment.
        let scalars = 15
        let size = MemoryLayout<SIMD2<Float>>.size + scalars * MemoryLayout<Float>.size
        XCTAssertEqual(MemoryLayout<HorizonUniforms>.size, size)
        XCTAssertEqual(MemoryLayout<HorizonUniforms>.alignment, MemoryLayout<SIMD2<Float>>.alignment)
        XCTAssertEqual(MemoryLayout<HorizonUniforms>.stride, 72)
    }
}
