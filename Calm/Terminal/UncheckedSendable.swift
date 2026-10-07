/// Carries a non-Sendable value across an isolation boundary we know is safe (same thread).
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) {
        self.value = value
    }
}
