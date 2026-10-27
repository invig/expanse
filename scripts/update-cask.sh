#!/bin/bash
# Points the Homebrew cask (Casks/expanse.rb in invig/homebrew-tap) at a release: sets its version
# and the zip's SHA-256, and commits that to the tap through GitHub's API, so there's no clone to
# keep. release.sh runs it after publishing; run it by hand to redo one.
#
# Usage: scripts/update-cask.sh <version> <zip>
#        CASK_BRANCH=test scripts/update-cask.sh ...   # commit to another branch of the tap
set -euo pipefail

VERSION="$1"
ZIP="$2"
TAP="invig/homebrew-tap"
FILE="Casks/expanse.rb"
BRANCH="${CASK_BRANCH:-main}"
SHA256=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

blob=$(gh api "repos/$TAP/contents/$FILE?ref=$BRANCH" --jq .sha)
current=$(gh api "repos/$TAP/contents/$FILE?ref=$BRANCH" -H "Accept: application/vnd.github.raw")
updated=$(sed -E -e "s/^  version \".*\"$/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"$/  sha256 \"$SHA256\"/" <<<"$current")

if ! grep -qx "  version \"$VERSION\"" <<<"$updated" || ! grep -qx "  sha256 \"$SHA256\"" <<<"$updated"; then
  echo "Couldn't find the version and sha256 lines in $TAP/$FILE." >&2
  exit 1
fi
if [[ "$updated" == "$current" ]]; then
  echo "The cask is already at $VERSION."
  exit 0
fi

gh api -X PUT "repos/$TAP/contents/$FILE" -f message="Expanse $VERSION" -f branch="$BRANCH" \
  -f sha="$blob" -f content="$(base64 <<<"$updated")" --jq .commit.html_url
