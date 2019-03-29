# xcodes

Manage the Xcodes installed on your Mac

## Installation

### Download a release (Preferred)

Download the latest release from the [Releases](https://github.com/interstateone/xcodes/releases) page. These are Developer ID-signed release builds and don't require Xcode to already be installed in order to use.

## Using [Mint](https://github.com/yonaskolb/Mint)

```sh
mint install interstateone/xcodes
```

### Build from source

<details>
<summary>Details</summary>

Building from source requires Xcode, so it's not an option for setting up a computer from scratch.

```sh
git clone https://github.com/interstateone/xcodes
cd xcodes
make install
# or, if /usr/local/ isn't in your PATH
PREFIX=/your/install/directory make install
```

While installing, you may get the following output:

```
swift build -Xswiftc "-target" -Xswiftc "x86_64-apple-macosx10.13"
error: terminated(72): xcrun --sdk macosx --find xctest output:

```

If that occurs, it means you need to select a version of Xcode. You can do this with `xcode-select` or by choosing a Command Line Tools option in Xcode's preferences Locations tab. 
</details>

## Usage

E.g. `xcodes install 10.1`

You'll then be prompted to enter your Apple ID username and password. You can also provide these with the `XCODES_USERNAME` and `XCODES_PASSWORD` environment variables.

### Commands

- `list`: Lists the versions of Xcode available to download
- `install <version>`: Downloads and installs a version of Xcode
- `installed`: Lists the versions of Xcodes that are installed in /Applications on your computer
- `update`: Updates the list of available versions of Xcode

## Development

Notable design decisions are recorded in [DECISIONS.md](./DECISIONS.md). The Apple authentication flow is described in [Apple.paw](./Apple.paw), which will allow you to play with the API endpoints that are involved using the [Paw](https://paw.cloud) app.

## Credit

[`xcode-install`](https://github.com/xcpretty/xcode-install) and [fastlane/spaceship](https://github.com/fastlane/fastlane/tree/master/spaceship) both deserve credit for figuring out the hard parts of what makes this possible.
