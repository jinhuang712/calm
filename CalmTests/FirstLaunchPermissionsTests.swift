@testable import Calm
import Foundation
import Testing

struct FirstLaunchPermissionsTests {
    @Test func `a build that was never asked asks`() {
        #expect(FirstLaunchPermissions.shouldAsk(saved: nil, current: "ab12"))
    }

    @Test func `a new build of the same version asks again`() {
        #expect(FirstLaunchPermissions.shouldAsk(saved: "ab12", current: "cd34"))
    }

    @Test func `the build that was asked does not ask twice`() {
        #expect(!FirstLaunchPermissions.shouldAsk(saved: "ab12", current: "ab12"))
    }

    @Test func `the identity is the same for one build and is never empty`() {
        let identity = FirstLaunchPermissions.buildIdentity()
        #expect(!identity.isEmpty)
        #expect(identity == FirstLaunchPermissions.buildIdentity())
    }
}
