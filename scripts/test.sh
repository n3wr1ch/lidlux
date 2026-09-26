#!/bin/zsh
# Command Line Tools 또는 Xcode 환경에서 Swift Testing을 실행한다. 사용법: ./scripts/test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DEVELOPER_DIR_PATH=$(xcode-select -p)
if [[ "$DEVELOPER_DIR_PATH" == */CommandLineTools ]]; then
    swift test --build-system native \
        -Xswiftc -F -Xswiftc "$DEVELOPER_DIR_PATH/Library/Developer/Frameworks" \
        -Xswiftc -plugin-path -Xswiftc "$DEVELOPER_DIR_PATH/usr/lib/swift/host/plugins/testing" \
        -Xlinker -F -Xlinker "$DEVELOPER_DIR_PATH/Library/Developer/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
else
    swift test
fi
