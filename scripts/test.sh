#!/bin/zsh
# Command Line Tools(Xcode 없음) 환경에서 Swift Testing 테스트를 실행한다. 사용법: ./scripts/test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
CLT=$(xcode-select -p)
swift test --build-system native \
    -Xswiftc -F -Xswiftc "$CLT/Library/Developer/Frameworks" \
    -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" \
    -Xlinker -F -Xlinker "$CLT/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Library/Developer/Frameworks"
