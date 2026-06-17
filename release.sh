#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./release.sh --version VERSION --team-id TEAM_ID
  ./release.sh VERSION TEAM_ID

Runs the release build steps starting at `make clean`.
EOF
}

VERSION=""
TEAMID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            VERSION="${2:-}"
            shift 2
            ;;
        -t|--team-id)
            TEAMID="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"
            elif [[ -z "$TEAMID" ]]; then
                TEAMID="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$VERSION" || -z "$TEAMID" ]]; then
    usage >&2
    exit 1
fi

echo "Cleaning build artifacts"
make clean

echo "Creating signed zip"
make zip

echo "Creating Homebrew bottle for $VERSION"
make bottle VERSION="$VERSION"

echo "Duplicating bottle for expected platform filenames"
cp "xcodes-$VERSION.mojave.bottle.tar.gz" "xcodes-$VERSION.arm64_mojave.bottle.tar.gz"
cp "xcodes-$VERSION.mojave.bottle.tar.gz" "xcodes-$VERSION.macos.i386.bottle.tar.gz"
cp "xcodes-$VERSION.mojave.bottle.tar.gz" "xcodes-$VERSION.macos.arm64.bottle.tar.gz"

echo "Notarizing release build with team ID $TEAMID"
make notarize TEAMID="$TEAMID"

cat <<EOF

Release assets are ready:
  xcodes.zip
  xcodes-$VERSION.mojave.bottle.tar.gz
  xcodes-$VERSION.arm64_mojave.bottle.tar.gz
  xcodes-$VERSION.macos.i386.bottle.tar.gz
  xcodes-$VERSION.macos.arm64.bottle.tar.gz

Next:
  1. Push the version bump commit and tag when ready:
     git push --follow-tags
  2. Edit the draft release created by Release Drafter to point at the new tag.
  3. Set the release title to $VERSION.
  4. Add the release assets listed above.
  5. Publish the release.
  6. Update the Homebrew bottle.
EOF
