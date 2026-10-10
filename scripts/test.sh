#!/bin/sh
# Runs the test suite. With Command Line Tools only, swift test cannot find
# the TestingMacros plugin, so pass its directory explicitly.
set -eu
cd "$(dirname "$0")/.."
exec swift test \
    -Xswiftc -plugin-path \
    -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
    "$@"
