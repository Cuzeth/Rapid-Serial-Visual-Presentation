import SwiftUI

extension Binding where Value == Bool {
    /// A Boolean binding that is `true` while `source` holds a value.
    ///
    /// Used to drive `alert(isPresented:)` from optional state: presentation
    /// happens by assigning the optional, and dismissing the alert (setting
    /// the binding to `false`) clears it back to `nil`.
    init<T>(isPresent source: Binding<T?>) {
        self.init(
            get: { source.wrappedValue != nil },
            set: { if !$0 { source.wrappedValue = nil } }
        )
    }
}
