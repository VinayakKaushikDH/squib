// Standalone test runner for SquibCore.
// Invokes Swift Testing's entry point directly, bypassing SPM's test bundle runner
// which requires a formal Testing product dependency to activate swift-testing mode.
//
// Usage: swift run squibTestRunner

@_spi(ForToolsIntegrationOnly) import Testing

await Testing.__swiftPMEntryPoint() as Never
