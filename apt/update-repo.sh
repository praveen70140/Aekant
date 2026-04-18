#!/bin/bash
# update-repo.sh - Generates APT repository metadata

set -e

REPO_DIR="repo-apt"
mkdir -p "$REPO_DIR"

# Copy all .deb files to the repo directory
cp *.deb "$REPO_DIR/" || true

cd "$REPO_DIR"

# 1. Generate Packages file
dpkg-scanpackages --multiversion . > Packages
gzip -k -f Packages

# 2. Generate Release files
apt-ftparchive release . > Release

# 3. Sign the Release file if GPG key is provided
if [ -n "$GPG_KEY_ID" ]; then
    echo "Signing repository with key $GPG_KEY_ID"
    gpg --batch --yes --default-key "$GPG_KEY_ID" -abs -o Release.gpg Release
    gpg --batch --yes --default-key "$GPG_KEY_ID" --clearsign -o InRelease Release
fi

echo "APT repository metadata updated."
