import Foundation

// SwiftPM requires an executable entry. The target links with -e _NSExtensionMain,
// so the SDK's Foundation extension bootstrap, rather than this empty main, runs.
