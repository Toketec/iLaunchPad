import Foundation
import Testing
@testable import iLaunchPad

struct ApplicationRemovalTests {
    typealias Policy = ApplicationRemovalPolicy

    private func allowed(_ path: String, _ id: String,
                         roots: [URL] = [URL(fileURLWithPath: "/Applications")]) -> Bool {
        Policy.permittedPath(URL(fileURLWithPath: path), bundleID: id,
                             ownBundleID: "local.ilaunchpad.app", applicationRoots: roots)
    }

    @Test func protectsSystemButAllowsIndependentAppleApplications() {
        #expect(allowed("/Applications/Pages Creator Studio.app", "com.apple.Pages"))
        #expect(allowed("/Applications/Xcode.app", "com.apple.dt.Xcode"))
        #expect(!allowed("/Applications/Safari.app", "com.apple.Safari"))
        #expect(!allowed("/System/Applications/Mail.app", "com.apple.mail"))
        #expect(!allowed("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app", "com.apple.Safari"))
    }

    @Test func rejectsSelfNestedHelpersAndLookalikeRoots() {
        #expect(!allowed("/Applications/iLaunchPad.app", "local.ilaunchpad.app"))
        #expect(!allowed("/Applications/Host.app/Contents/Helper.app", "vendor.helper"))
        #expect(!allowed("/Applications-other/Foo.app", "vendor.foo"))
        #expect(!allowed("/Applications/Foo", "vendor.foo"))
        #expect(!allowed("/Applications/Foo.app", ""))
    }

    @Test func acceptsOnlyDescendantsOfExplicitApplicationRoots() {
        let userRoot = URL(fileURLWithPath: "/Users/example/Applications")
        #expect(allowed("/Users/example/Applications/Foo.app", "vendor.foo", roots: [userRoot]))
        #expect(!allowed("/Users/example/ApplicationsBackup/Foo.app", "vendor.foo", roots: [userRoot]))
        #expect(!allowed("/Users/example/Desktop/Foo.app", "vendor.foo", roots: [userRoot]))
    }
}
