# Releasing the xcodes CLI

Run the release command from this repository on the maintainer’s Mac after the changes to ship are merged into GitHub main.

| Task | Command |
| --- | --- |
| Preview a release | `./Scripts/release VERSION --dry-run` |
| Publish a stable release | `./Scripts/release VERSION` |
| Continue an interrupted release | `./Scripts/release --resume VERSION` |

Use the actual requested version in place of `VERSION`. Run a dry run for planning or readiness checks. Publish or resume only when explicitly asked to do so for that version. If an authorized publication saves a release and then stops, continue with its printed resume command from the same checkout. Verify that it reports both the GitHub release URL and the Homebrew tap commit before reporting completion.

The [release runbook](README.md#releasing-a-new-version-of-xcodes) covers credentials, notes, and recovery.
