# xcodes

Manage the Xcodes installed on your Mac

## Installation

### From source

```sh
git clone https://github.com/interstateone/xcodes
cd xcodes
swift build -Xswiftc "-target" -Xswiftc "x86_64-apple-macosx10.13"
cp $(swift build --show-bin-path)/xcodes /usr/local/bin/xcodes
```

## Usage

- `list`: Lists the versions of Xcode available to download
- `install <version>`: Downloads and installs a version of Xcode
- `installed`: Lists the versions of Xcodes that are installed in /Applications on your computer
- `update`: Updates the list of available versions of Xcode

## Development

Notable design decisions are recorded in [DECISIONS.md](./DECISIONS.md). The Apple authentication flow is described in [Apple.paw](./Apple.paw), which will allow you to play with the API endpoints that are involved using the [Paw](https://paw.cloud) app.

## Credit

[`xcode-install`](https://github.com/xcpretty/xcode-install) and [fastlane/spaceship](https://github.com/fastlane/fastlane/tree/master/spaceship) both deserve credit for figuring out the hard parts of what makes this possible.
