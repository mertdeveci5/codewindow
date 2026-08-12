#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
cd "$repo_dir"

/usr/bin/swift build --product CodeWindowTests
test_binary=$(/usr/bin/swift build --show-bin-path)/CodeWindowTests
/usr/bin/codesign --verify --strict "$test_binary"
"$test_binary"
