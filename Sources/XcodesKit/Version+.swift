import Version

public extension Version {
    func isEqualWithoutPrerelease(_ other: Version) -> Bool {
        return major == other.major && minor == other.minor && patch == other.patch
    }
}
