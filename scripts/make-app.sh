#!/bin/sh
# Builds a release binary and wraps it in dist/MC6 Virtual.app with an ad-hoc signature.
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product MC6App
bin="$(swift build -c release --show-bin-path)/MC6App"

app="dist/MC6 Virtual.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/MC6App"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"

# Self-test: the binary is in place and the signature verifies.
test -x "$app/Contents/MacOS/MC6App"
codesign --verify --strict "$app"
echo "Built $app"
