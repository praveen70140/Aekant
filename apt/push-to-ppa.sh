#!/bin/bash
# push-to-ppa.sh - Prepares and uploads source package to Launchpad

set -e

VERSION=$1
LP_USER=$2
PPA_NAME=$3
GPG_KEY_ID=$4
GPG_PASSPHRASE=$5

if [ -z "$VERSION" ] || [ -z "$LP_USER" ] || [ -z "$PPA_NAME" ]; then
    echo "Usage: $0 <version> <lp_user> <ppa_name> [gpg_key_id] [gpg_passphrase]"
    exit 1
fi

# Distributions to target
DISTS=("focal" "jammy" "noble")
PROJECT_ROOT=$(pwd)

# Create a clean work directory
WORK_DIR=$(mktemp -d)
echo "Working in $WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

# 1. Prepare the common .orig.tar.xz
# Launchpad requires an .orig.tar.xz that contains the upstream source.
# For this binary package, we'll create one that matches the expected structure.
SOURCE_DIR_NAME="aekant-browser-$VERSION"
mkdir -p "$WORK_DIR/$SOURCE_DIR_NAME"

# Try to extract with strip-components=1, but fall back if it fails (i.e. if no top-level dir)
if ! tar -xf "$PROJECT_ROOT/aekant.tar.xz" -C "$WORK_DIR/$SOURCE_DIR_NAME" --strip-components=1 2>/dev/null; then
    tar -xf "$PROJECT_ROOT/aekant.tar.xz" -C "$WORK_DIR/$SOURCE_DIR_NAME"
fi

# Create the .orig.tar.xz in the parent of where we will build
cd "$WORK_DIR"
tar -cJf "aekant-browser_$VERSION.orig.tar.xz" "$SOURCE_DIR_NAME"

# 2. Setup dput config
cat <<EOF > "$WORK_DIR/dput.cf"
[aekant-ppa]
fqdn = ppa.launchpad.net
method = ftp
incoming = ~${LP_USER}/ubuntu/${PPA_NAME}/
login = anonymous
allow_unsigned_uploads = 0
EOF

# 3. GPG Wrapper for debsign if passphrase is provided
if [ -n "$GPG_PASSPHRASE" ]; then
    GPG_WRAPPER="$WORK_DIR/gpg-wrapper"
    cat <<EOF > "$GPG_WRAPPER"
#!/bin/bash
printf "%s" "$GPG_PASSPHRASE" | exec gpg --batch --pinentry-mode loopback --passphrase-fd 0 "\$@"
EOF
    chmod +x "$GPG_WRAPPER"
    export DEBSIGN_PROGRAM="$GPG_WRAPPER"
fi

# 4. Loop through distributions and build source packages
DATE=$(date -R)

for DIST in "${DISTS[@]}"; do
    echo "--------------------------------------------------------"
    echo "Processing for $DIST..."
    
    PPA_VERSION="${VERSION}-0ppa1~ubuntu${DIST}"
    DIST_DIR="$WORK_DIR/aekant-browser-$DIST"
    
    # Copy the prepared source tree
    cp -r "$WORK_DIR/$SOURCE_DIR_NAME" "$DIST_DIR"
    cp -r "$PROJECT_ROOT/apt/debian" "$DIST_DIR/debian"
    
    # Update changelog for this distribution
    cd "$DIST_DIR"
    sed -i "s/#VERSION#/$PPA_VERSION/g" debian/changelog
    sed -i "s/#DIST#/$DIST/g" debian/changelog
    sed -i "s/#DATE#/$DATE/g" debian/changelog
    
    # Build source package (-S)
    # -d skips build-deps check (useful for binary-only packaging in CI)
    # -us -uc skips signing at this stage (we use debsign later)
    dpkg-buildpackage -S -d -us -uc
    
    # Sign and Upload
    cd "$WORK_DIR"
    CHANGES_FILE="aekant-browser_${PPA_VERSION}_source.changes"
    
    if [ -n "$GPG_KEY_ID" ]; then
        echo "Signing $CHANGES_FILE..."
        debsign -k "$GPG_KEY_ID" "$CHANGES_FILE"
        
        echo "Uploading to Launchpad ($DIST)..."
        dput -c "$WORK_DIR/dput.cf" aekant-ppa "$CHANGES_FILE"
    else
        echo "No GPG_KEY_ID provided, skipping upload for $DIST."
    fi
done

echo "All done!"
