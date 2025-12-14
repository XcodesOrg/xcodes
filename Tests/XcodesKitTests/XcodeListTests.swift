import XCTest
import Version
@testable import XcodesKit

class XcodeListTests: XCTestCase {

    func xcodeFromVersion(version: Version?) -> Xcode
    {
        return Xcode(version: version!,
                     url: URL(fileURLWithPath: "https://developer.apple.com/Xcode_example.app"),
                     filename: "Xcode_example.app",
                     releaseDate: nil)
    }
    
    let versions = [
  
        // Single version
        Version(major: 1, minor: 1, patch: 1, prereleaseIdentifiers: [], buildMetadataIdentifiers: ["1.1.1.build1"]),
        
        // 2 versions with the same build, one is beta
        Version(major: 1, minor: 2, patch: 1, prereleaseIdentifiers: [], buildMetadataIdentifiers: ["1.2.1.build1"]),
        Version(major: 1, minor: 2, patch: 1, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: ["1.2.1.build1"]),

        // 2 versions with the same build, one is beta (other GM)
        Version(major: 1, minor: 3, patch: 1, prereleaseIdentifiers: ["GM"], buildMetadataIdentifiers: ["1.3.1.build1"]),
        Version(major: 1, minor: 3, patch: 1, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: ["1.3.1.build1"]),
        
        // 2 versions with no buildMetaIdentifiers.
        Version(major: 1, minor: 4, patch: 1, prereleaseIdentifiers: [], buildMetadataIdentifiers: []),
        Version(major: 1, minor: 4, patch: 2, prereleaseIdentifiers: [], buildMetadataIdentifiers: []),
    ]
    
    let filteredVersionsExpected = [
        // Single version
        Version(major: 1, minor: 1, patch: 1, prereleaseIdentifiers: [], buildMetadataIdentifiers: ["1.1.1.build1"]),
    
        // 2 versions with the same build, one is beta
        Version(major: 1, minor: 2, patch: 1, prereleaseIdentifiers: [], buildMetadataIdentifiers: ["1.2.1.build1"]),
        //Version(major: 1, minor: 2, patch: 1, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: ["1.2.1.build1"]),

        // 2 versions with the same build, one is beta (other GM)
        Version(major: 1, minor: 3, patch: 1, prereleaseIdentifiers: ["GM"], buildMetadataIdentifiers: ["1.3.1.build1"]),
        //Version(major: 1, minor: 3, patch: 1, prereleaseIdentifiers: ["beta"], buildMetadataIdentifiers: ["1.3.1.build1"]),

        // 2 versions with no buildMetaIdentifiers.
        Version(major: 1, minor: 4, patch: 1, prereleaseIdentifiers: [], buildMetadataIdentifiers: []),
        Version(major: 1, minor: 4, patch: 2, prereleaseIdentifiers: [], buildMetadataIdentifiers: []),
    ]
    
    var filteredVersions : [Version] = []
        
    override func setUpWithError() throws {
        let xcodes = versions.map(xcodeFromVersion)
        let filteredXcodes = XcodeList.filterPrereleasesThatMatchReleaseBuildMetadataIdentifiers(xcodes)
        filteredVersions = filteredXcodes.map { $0.version }
    }
    
    func test_filterPrereleasesThatMatchReleaseBuildMetadataIdentifiers() {
        XCTAssertEqual(filteredVersions.sorted(), filteredVersionsExpected.sorted())
    }
}
