#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: Scripts/appcast-notes.sh <tag>

Copies the notes of a GitHub release into the appcast.xml attached to it, so
Sparkle's update window shows the same notes as the release page. Run it
again after editing the notes; the Release notes workflow does that on every
edit.

Needs gh signed in, or GH_TOKEN. Uses GITHUB_REPOSITORY when set, otherwise
the repository of the current checkout.
EOF
}

[[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; exit 0; }
[[ $# -eq 1 ]] || { usage >&2; exit 64; }
tag="$1"
repo="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if ! gh release download "$tag" -R "$repo" -p appcast.xml -D "$work" 2>/dev/null; then
  echo "appcast-notes.sh: $tag has no appcast.xml, so there is nothing to update."
  exit 0
fi

gh release view "$tag" -R "$repo" --json body --jq .body > "$work/notes.md"
if [[ -s "$work/notes.md" ]]; then
  # GitHub renders the notes exactly like the release page: links, mentions,
  # task lists and all.
  gh api markdown -f mode=gfm -f context="$repo" -F text=@"$work/notes.md" > "$work/notes.html"
else
  : > "$work/notes.html"
fi

python3 - "$work/appcast.xml" "$work/notes.html" <<'EOF'
import sys
import xml.etree.ElementTree as ET

appcast, notes = sys.argv[1], sys.argv[2]
ET.register_namespace("sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle")
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")
body = open(notes, encoding="utf-8").read().strip()
style = (
    '<meta name="color-scheme" content="light dark">'
    "<style>body { font: -apple-system-body; margin: 12px 16px; }"
    " img { max-width: 100%; } code { font-size: 0.9em; }</style>"
)
tree = ET.parse(appcast)
items = tree.getroot().findall("./channel/item")
if not items:
    sys.exit("appcast-notes.sh: the appcast has no items.")
link = "{http://www.andymatuschak.org/xml-namespaces/sparkle}releaseNotesLink"
for item in items:
    for old in item.findall("description") + item.findall(link):
        item.remove(old)
    if body:
        description = ET.Element("description")
        description.text = style + body
        title = item.find("title")
        item.insert(list(item).index(title) + 1 if title is not None else 0, description)
tree.write(appcast, encoding="utf-8", xml_declaration=True)
EOF

gh release upload "$tag" "$work/appcast.xml" -R "$repo" --clobber
echo "Updated the notes in the appcast of $tag."
