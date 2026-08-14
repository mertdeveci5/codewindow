# Set up CodeWindow

Install the latest CodeWindow release on this Mac. Do not remove quarantine attributes or bypass Gatekeeper.

```sh
set -euo pipefail

setup_dir="$(mktemp -d /tmp/codewindow-setup.XXXXXX)"
cleanup() {
  /usr/bin/find "$setup_dir" -depth -delete
}
trap cleanup EXIT

appcast="$setup_dir/appcast.xml"
curl -fsSL "https://github.com/mertdeveci5/codewindow/releases/latest/download/appcast.xml" -o "$appcast"
archive_url="$(/usr/bin/xmllint --nonet --xpath 'string(/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"][1]/*[local-name()="enclosure"]/@url)' "$appcast")"

case "$archive_url" in
  https://github.com/mertdeveci5/codewindow/releases/download/v*/CodeWindow-v*-macOS-universal.zip) ;;
  *) echo "CodeWindow returned an unexpected download URL." >&2; exit 1 ;;
esac

archive_name="${archive_url##*/}"
archive="$setup_dir/$archive_name"
curl -fsSL "$archive_url" -o "$archive"
curl -fsSL "$archive_url.sha256" -o "$archive.sha256"
(cd "$setup_dir" && /usr/bin/shasum -a 256 -c "$archive_name.sha256")

/usr/bin/ditto -x -k "$archive" "$setup_dir"
/usr/sbin/spctl --assess --type execute --verbose=4 "$setup_dir/CodeWindow.app"

if [ -d "/Applications/CodeWindow.app" ]; then
  target="/Applications/CodeWindow.app"
else
  /bin/mkdir -p "$HOME/Applications"
  target="$HOME/Applications/CodeWindow.app"
fi

/usr/bin/osascript -e 'if application id "dev.codewindow.app" is running then tell application id "dev.codewindow.app" to quit' 2>/dev/null || true
previous_app="$setup_dir/Previous CodeWindow.app"
if [ -d "$target" ]; then
  /bin/mv "$target" "$previous_app"
fi
if ! /usr/bin/ditto "$setup_dir/CodeWindow.app" "$target"; then
  if [ -d "$previous_app" ]; then
    /bin/mv "$previous_app" "$target"
  fi
  exit 1
fi

"$target/Contents/Helpers/codewindow-install" install
/usr/bin/open "$target"
```

Restart any Codex, Claude Code, or Pi sessions that were already open. In Codex, run `/hooks` and trust the CodeWindow hooks if asked.
