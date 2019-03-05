# Decisions

This file exists to provide a historical record of the motivation for important technical decisions in the project. It's inspired by Architectural Decision Records, but the implementation is intentionally simpler than usual. When a new decision is made, append it to the end of the file with a header. Decisions can be changed later. This is a reflection of real life, not a contract that has to be followed.

## Code Organization

Xcodes is primarily a command-line tool. The command-line UI code should live in the xcodes executable target. Code that performs downloading and installation should live in the XcodesKit library target so it can be tested without running xcodes in a shell. Hypothetically XcodesKit should be implemented in a way that allows it to be used in other contexts, like a GUI app. This isn't the primary goal right now so there might be oversights where a CLI context is assumed, but try to avoid things like `exit` system calls.

## Asynchrony

Using PromiseKit to model asynchronous work. This isn't necessary for a CLI app since it's assumed that the main thread is going to be blocked while work is performed. It provides a little more flexibility for a little more overhead though, and I think it's an okay tradeoff for now.

## Dependency Injection

This is a small project, but because its purpose involves long-running tasks it can be really valuable to have tests that automatically verify its behaviour. A lot of Swift test double designs involve protocols and constructor injection (or worse), which I want to avoid. Another option that I've seen and am curious about is Point Free's Environment type. It looks a lot simpler to implement and grow with a codebase, but still allows setting up test double for tests.

- https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
- https://www.pointfree.co/episodes/ep18-dependency-injection-made-comfortable
- https://vimeo.com/291588126

## Privilege Escalation

There's no good, supported options for privilege escalation on macOS for Swift CLI programs, and xcodes needs to perform a few things as root to fully set up Xcode.

- `SMJobBless`: requires the privileged helper to be shipped inside an app bundle
- `system`: unavailable to Swift
- Run xcodes with sudo: xcodes doesn't need elevated privileges the entire time, and means simple programmer mistakes can have bad consequences
- `AuthorizationExecuteWithPrivileges`: deprecated, and unavailable to Swift
- Reverse engineer functionality requiring sudo: only works for some tasks and is brittle. For example, `xcodebuild -license accept` could be replicated with `authopen` prompting for privilege to write to `/Library/Preferences/com.apple.dt.xcode.plist`.
- Prompt with `readpassphrase` and pipe to sudo in Process: The downside is the sudoer's passphrase is now in our process for a period of time, but I think this is the least bad option from a mostly-practical perspective.
