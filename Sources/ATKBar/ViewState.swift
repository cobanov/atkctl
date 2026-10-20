import SwiftUI

// Name the property-wrapper type explicitly: newer SDKs also expose a State macro
// whose SwiftUIMacros plugin is not shipped with Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>
