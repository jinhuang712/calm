@testable import CalmAgents
import CalmModel
import Foundation
import Testing

struct AgentMarkTests {
    @Test func `every agent has a mark the sidebar can draw`() {
        #expect(Agents.adapters.count == AgentKind.allCases.count)
        for adapter in Agents.adapters {
            let mark = adapter.mark
            #expect(!mark.shapes.isEmpty, "\(adapter.kind)")
            #expect(mark.viewBox.side > 0)
            #expect(mark.scale > 0 && mark.scale <= 1)
            for shape in mark.shapes {
                // The sidebar's path reader knows lines, curves and closes; not arcs.
                #expect(shape.path.range(of: "^[MmLlHhVvCcSsQqTtZz0-9.,\\s-]+$", options: .regularExpression) != nil, "\(adapter.kind)")
                for hex in Self.colors(shape.fill) {
                    #expect(hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil, "\(adapter.kind): \(hex)")
                }
            }
        }
    }

    @Test func `marks move in their own ways`() {
        let motions = Agents.adapters.map(\.mark.motion)
        #expect(Set(motions.map { "\($0)" }).count == motions.count)
    }

    private static func colors(_ fill: AgentMarkArt.Fill) -> [String] {
        switch fill {
        case let .color(dark, light): [dark, light]
        case let .gradient(stops): stops
        }
    }
}
