#!/usr/bin/env bash
#
# Run the CliplexKit test suite (Swift Testing).
#
# The active toolchain is the Command Line Tools, where the Swift Testing
# runtime (Testing.framework + lib_TestingInterop.dylib) is present but not on
# the default search path, so we point the compiler/linker at it explicitly.
# Also injects safe.bareRepository=all via env (the machine's global git config
# sets it to 'explicit', which blocks SwiftPM's bare dependency repos).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.bareRepository
export GIT_CONFIG_VALUE_0=all

FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

exec swift test \
    --disable-xctest --enable-swift-testing \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
