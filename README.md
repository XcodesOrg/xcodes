# xcodes

Manage the Xcodes installed on your Mac

![CI Status](https://github.com/RobotsAndPencils/xcodes/workflows/CI/badge.svg)

## Installation

### Homebrew (Preferred)

```sh
brew install robotsandpencils/made/xcodes
```

These are Developer ID-signed and notarized release builds and don't require Xcode to already be installed in order to use.

**Other methods:**

<details>
<summary>Download a release</summary>

Download the latest release from the [Releases](https://github.com/RobotsAndPencils/xcodes/releases) page. These are Developer ID-signed release builds and don't require Xcode to already be installed in order to use.
</details>

<details>
<summary>Using <a href="https://github.com/yonaskolb/Mint">Mint</a></summary>

```sh
mint install RobotsAndPencils/xcodes
```
</details>

<details>
<summary>Build from source</summary>

Building from source requires Xcode 11.0 or later, so it's not an option for setting up a computer from scratch.

```sh
git clone https://github.com/RobotsAndPencils/xcodes
cd xcodes
make install
# or, if /usr/local/ isn't in your PATH
PREFIX=/your/install/directory make install
```

While installing, you may get the following output:

```
swift build
error: terminated(72): xcrun --sdk macosx --find xctest output:

```

If that occurs, it means you need to select a version of Xcode. You can do this with `xcode-select` or by choosing a Command Line Tools option in Xcode's preferences Locations tab.
</details>

## Usage

Install a specific version of Xcode using a command like one of these:

```
xcodes install 10.2.1
xcodes install 11 Beta 7
xcodes install 11.2 GM seed
```

You'll then be prompted to enter your Apple ID username and password. You can also provide these with the `XCODES_USERNAME` and `XCODES_PASSWORD` environment variables.

After successfully authenticating, xcodes will save your Apple ID password into the keychain and will remember your Apple ID for future use. If you need to use a different Apple ID than the one that's remembered, set the `XCODES_USERNAME` environment variable.

xcodes will download and install the version you asked for so that it's ready to use.

```
(1/6) Downloading Xcode 11.2.0: 100%
(2/6) Unarchiving Xcode (This can take a while)
(3/6) Moving Xcode to /Applications/Xcode-11.2.0.app
(4/6) Moving Xcode archive Xcode-11.2.0.xip to the Trash
(5/6) Checking security assessment and code signing
(6/6) Finishing installation
xcodes requires superuser privileges in order to finish installation.
macOS User Password:

Xcode 11.2.0 has been installed to /Applications/Xcode-11.2.0.app
```

### Commands

- `install <version>`: Download and install a specific version of Xcode
- `installed`: List the versions of Xcode that are installed
- `list`: List all versions of Xcode that are available to install
- `select`: Change the selected Xcode
- `uninstall <version>`: Uninstall a specific version of Xcode
- `update`: Update the list of available versions of Xcode
- `version`: Print the version number of xcodes itself

## Development

Notable design decisions are recorded in [DECISIONS.md](./DECISIONS.md). The Apple authentication flow is described in [Apple.paw](./Apple.paw), which will allow you to play with the API endpoints that are involved using the [Paw](https://paw.cloud) app.

[`xcode-install`](https://github.com/xcpretty/xcode-install) and [fastlane/spaceship](https://github.com/fastlane/fastlane/tree/master/spaceship) both deserve credit for figuring out the hard parts of what makes this possible.

## Contact

<a href="http://www.robotsandpencils.com"><img src="R&PLogo.png" width="153" height="74" /></a>

Made with ❤️ by [Robots & Pencils](http://www.robotsandpencils.com)

[Twitter](https://twitter.com/robotsNpencils) | [GitHub](https://github.com/robotsandpencils)
