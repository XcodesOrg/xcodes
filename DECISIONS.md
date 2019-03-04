# Decisions

## Code Organization

Xcodes is primarily a command-line tool. The command-line UI code should live in the xcodes executable target. Code that performs downloading and installation should live in the XcodesKit library target so it can be tested without running xcodes in a shell. Hypothetically XcodesKit should be implemented in a way that allows it to be used in other contexts, like a GUI app. This isn't the primary goal right now so there might be oversights where a CLI context is assumed, but try to avoid things like `exit` system calls.

## Asynchrony

Using PromiseKit to model asynchronous work. This isn't necessary for a CLI app since it's assumed that the main thread is going to be blocked while work is performed. It provides a little more flexibility for a little more overhead though, and I think it's an okay tradeoff for now.

## Privilege Escalation

There's no good, supported options for privilege escalation on macOS for Swift CLI programs, and xcodes needs to perform a few things as root to fully set up Xcode.

- `SMJobBless`: requires the privileged helper to be shipped inside an app bundle
- `system`: unavailable to Swift
- Run xcodes with sudo: xcodes doesn't need elevated privileges the entire time, and means simple programmer mistakes can have bad consequences
- `AuthorizationExecuteWithPrivileges`: deprecated, and unavailable to Swift
- Reverse engineer functionality requiring sudo: only works for some tasks and is brittle. For example, `xcodebuild -license accept` could be replicated with `authopen` prompting for privilege to write to `/Library/Preferences/com.apple.dt.xcode.plist`.
- Prompt with `readpassphrase` and pipe to sudo in Process: The downside is the sudoer's passphrase is now in our process for a period of time, but I think this is the least bad option from a mostly-practical perspective.
