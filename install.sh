#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
source_app="$project_dir/dist/GPT 用量.app"
installed_app='/Applications/GPT 用量.app'
stamp=$(/bin/date '+%Y%m%d-%H%M%S')
backup_dir="$project_dir/backups/$stamp"

[[ -d "$source_app" ]] || { print -u2 '请先运行 ./build.sh'; exit 1; }
mkdir -p "$backup_dir"

if [[ -d "$installed_app" ]]; then
  /usr/bin/ditto "$installed_app" "$backup_dir/GPT 用量.app"
fi

preference="$HOME/Library/Preferences/local.codex.gpt-quota.plist"
if [[ -f "$preference" ]]; then
  cp -p "$preference" "$backup_dir/local.codex.gpt-quota.plist"
fi

/usr/bin/pkill -x GPTQuota 2>/dev/null || true
for attempt in {1..40}; do
  /usr/bin/pgrep -x GPTQuota >/dev/null || break
  /bin/sleep 0.25
done
/usr/bin/pgrep -x GPTQuota >/dev/null && { print -u2 '旧进程未退出'; exit 1; }

/usr/bin/ditto "$source_app" "$installed_app"
/usr/bin/codesign --verify --deep --strict "$installed_app"
/usr/bin/open "$installed_app"

for attempt in {1..40}; do
  /usr/bin/pgrep -x GPTQuota >/dev/null && break
  /bin/sleep 0.25
done

/usr/bin/pgrep -fl GPTQuota
printf '已安装 2.1，可回退备份：%s\n' "$backup_dir"

