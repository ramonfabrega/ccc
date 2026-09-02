import CCCKit
import Testing

@Suite struct GridTests {
    @Test func renderedTrimsTrailingSpaces() {
        let grid = Grid(cols: 5, rows: 2, lines: ["ab   ", "     "], cursor: .init(col: 0, row: 0, visible: true))
        #expect(grid.rendered() == "ab\n")
        #expect(grid.rendered(trimTrailing: false) == "ab   \n     ")
    }
}

/// Fixture files live in Tests/CCCKitTests/Fixtures and are copied into the
/// test bundle.
enum Fixtures {
    static func url(_ relative: String) -> URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appending(path: relative)
    }
    static func data(_ relative: String) throws -> Data { try Data(contentsOf: url(relative)) }
}

import Foundation
