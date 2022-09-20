# `.xcode-version`

## Introduction

This is a proposal for a new standard for the iOS community: a text-based file that defines the Xcode version to use to compile and package a given iOS project.

This file is used by this CLI tool. It has also been used by the legacy `xcode-install` gem, as well as other similar projects, and has full support in _fastlane_'s actions as well. It's designed in a way that any tool in the future can pick it up, no matter if it's Ruby based, Swift, JavaScript, etc.

Similar to the [.ruby-version file](https://en.wikipedia.org/wiki/Ruby_Version_Manager), the `.xcode-version` file allows any CI system or IDE to automatically install and switch to the Xcode version needed for a given project to successfully compile your project.

## Filename

The filename must always be `.xcode-version`.

## File location

The file must be located in the same directory as your Xcode project/workspace, and you should add it to your versioning system (e.g. git).

## File content

The file content must be a simple string in a text file. The file may or may not end with an empty new line, this gem is responsible for stripping out the trailing `\n` (if used).

### Sample files

To define an official Xcode release

```txt
13.0
```

```txt
13.4.1
```

You can also use pre-releases

```txt
12.1 GM
```

```txt
14.0 Beta 6
```

Always following the same version naming listed by `xcodes list`.

**Note**: Be aware that pre-releases might be eventually taken down from Apple's servers, meaning that it won't allow you to have fully reproducible builds as you won't be able to download the Xcode release once it's gone.

It is recommended to only use non-beta releases in an `.xcode-version` file to have fully reproducible builds that you'll be able to run in a few years also. See also: https://ios-factor.com/dependencies
