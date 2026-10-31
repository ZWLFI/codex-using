#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
build_dir="$project_dir/build"
app="$project_dir/dist/GPT 用量.app"

rm -rf "$build_dir" "$app"
mkdir -p "$build_dir" "$app/Contents/MacOS" "$app/Contents/Resources"

/usr/bin/swiftc -parse-as-library -swift-version 5 -O \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework Charts \
  -framework ServiceManagement -framework UserNotifications \
  "$project_dir"/Sources/*.swift \
  -o "$app/Contents/MacOS/GPTQuota"

cp "$project_dir/Info.plist" "$app/Contents/Info.plist"
cp "$project_dir/assets/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - "$app"

"$app/Contents/MacOS/GPTQuota" --self-test
printf '已生成：%s\n' "$app"

