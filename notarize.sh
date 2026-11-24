#!/bin/sh
set -eu

if [ "$#" -ne 2 ] || [ ! -f "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <archive.zip> <Apple Developer team ID>" >&2
    exit 1
fi

archive=$1
team_id=$2
result=$(mktemp)
trap 'rm -f "$result"' EXIT

echo "Submitting $archive to Apple for notarization"
if ! xcrun notarytool submit "$archive" --keychain-profile AC_PASSWORD --team-id "$team_id" \
    --wait --timeout 30m --output-format json > "$result"; then
    cat "$result" >&2
    exit 1
fi

status=$(plutil -extract status raw -o - "$result")
submission_id=$(plutil -extract id raw -o - "$result")
if [ "$status" != Accepted ]; then
    echo "Notarization status: $status (submission $submission_id)" >&2
    xcrun notarytool log "$submission_id" --keychain-profile AC_PASSWORD --team-id "$team_id" >&2 || true
    exit 1
fi

echo "Notarization accepted (submission $submission_id)"
