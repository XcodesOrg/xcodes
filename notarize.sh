#!/bin/sh
#
# notarize.sh
#
# E.g. ./notarize.sh "test@example.com" "@keychain:altool" MyOrg xcodes.zip
#
# Adapted from https://github.com/keybase/client/blob/46f5df0aa64ff19198ba7b044bbb7cd907c0be9f/packaging/desktop/package_darwin.sh

file="$1"
team_id="$2"

echo "Uploading to notarization service"

result=$(xcrun notarytool submit "$file" \
    --keychain-profile "AC_PASSWORD" \
    --team-id "$team_id" \
    --wait) 

echo $result
