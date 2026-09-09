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

    func testDisabledAmbientMotionKeepsShaderInputsStableAsWallTimeAdvances() {
        let state = HorizonState(light: 1, warmth: 0.4, turn: 0.2, travel: 0.3, frozen: false)
        let first = HorizonUniforms(state: state, time: 10, ambient: false, meteorElapsed: nil, meteorSeed: 0)
        let later = HorizonUniforms(state: state, time: 90, ambient: false, meteorElapsed: 2, meteorSeed: 0)
        XCTAssertEqual(first, later)

        let moving = HorizonUniforms(state: state, time: 90, ambient: true, meteorElapsed: 2, meteorSeed: 0)
        XCTAssertNotEqual(first, moving)
    }

    func testFrozenHorizonSuppressesAmbientInputsEvenWhenMotionIsRequested() {
        let state = HorizonState(light: 1, warmth: 0.4, turn: 0.2, travel: 0.3, frozen: true)
        let first = HorizonUniforms(state: state, time: 10, ambient: true, meteorElapsed: nil, meteorSeed: 0)
        let later = HorizonUniforms(state: state, time: 90, ambient: true, meteorElapsed: 2, meteorSeed: 0)
        XCTAssertEqual(first, later)
        XCTAssertEqual(first.turn, Float(state.turn))
        XCTAssertEqual(first.warmth, Float(state.warmth))
    }
}
