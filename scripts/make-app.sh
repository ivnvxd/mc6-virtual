#!/bin/sh
# Builds a release binary and wraps it in dist/MC6 Virtual.app with an ad-hoc signature.
# The arguments go to swift build, for example `--arch arm64 --arch x86_64` for a universal app (needs Xcode).
# VERSION, if set, becomes the app version, for example VERSION=1.2.0.
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product MC6App "$@"
bin="$(swift build -c release --show-bin-path "$@")/MC6App"

app="dist/MC6 Virtual.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/MC6App"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
if [ -n "${VERSION:-}" ]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$app/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$VERSION" "$app/Contents/Info.plist"
fi
codesign --force --sign - "$app"

# Self-test: the binary is in place and the signature verifies.
test -x "$app/Contents/MacOS/MC6App"
codesign --verify --strict "$app"
echo "Built $app"
