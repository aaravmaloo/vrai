#!/bin/bash
set -euo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$scripts")"
vrai="$root"
ds="$root/prototype_ui/design-system"
logos="$ds/project/assets/Logos"
kit="$vrai/Packages/VraiKit"
assets="$vrai/App/Assets.xcassets"
render="$ds/scripts/render-png.mjs"

skip_render=0
if [ "${1:-}" = "--check-only" ]; then skip_render=2; fi
if [ "${1:-}" = "--no-render" ]; then skip_render=1; fi

check_icons() {
  local allowed used missing
  allowed="$(node -e 'for (const [n] of require(process.argv[1])) console.log(n)' "$ds/icons.json" | sort -u)"
  used="$(grep -rhoE '(systemName|systemImage|icon): *"[^"]+"' "$vrai/App" "$kit/Sources" "$vrai/Helpers" --include='*.swift' 2>/dev/null | sed -E 's/.*"([^"]+)"/\1/' | sort -u || true)"
  missing="$(comm -13 <(echo "$allowed") <(echo "$used") | sed '/^$/d' || true)"
  if [ -n "$missing" ]; then
    echo "Symbols not in icons.json:" >&2
    echo "$missing" >&2
    return 1
  fi
  echo "icons: $(echo "$used" | sed '/^$/d' | wc -l | tr -d ' ') symbols used, all in icons.json"
}

if [ "$skip_render" = 2 ]; then
  check_icons
  exit $?
fi

(cd "$ds" && npm run --silent tokens >/dev/null)
mkdir -p "$kit/Sources/VraiUI/Tokens" "$kit/Tests/VraiUITests/Resources"
cp "$ds/project/assets/SwiftUI/VraiTokens.swift" "$kit/Sources/VraiUI/Tokens/VraiTokens.swift"
cp "$ds/icons.json" "$kit/Tests/VraiUITests/Resources/icons.json"
echo "tokens: copied VraiTokens.swift and icons.json"

if [ "$skip_render" = 0 ]; then
  iconset="$assets/AppIcon.appiconset"
  mkdir -p "$iconset"
  for px in 16 32 64 128 256 512 1024; do
    node "$render" "$logos/vrai-app-icon.svg" "$px" "$iconset/icon_$px.png" >/dev/null
  done
  cat > "$iconset/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  echo "app icon: rendered 7 sizes from vrai-app-icon.svg"

  mark="$assets/VraiMark.imageset"
  mkdir -p "$mark"
  node "$render" "$logos/vrai-mark.svg" 256 "$mark/vrai-mark.png" >/dev/null
  node "$render" "$logos/vrai-mark.svg" 512 "$mark/vrai-mark@2x.png" >/dev/null
  cat > "$mark/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "vrai-mark.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "vrai-mark@2x.png", "idiom" : "universal", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
JSON

  color="$assets/VraiMarkColor.imageset"
  mkdir -p "$color"
  node "$render" "$logos/vrai-mark-color.svg" 256 "$color/vrai-mark-color.png" >/dev/null
  node "$render" "$logos/vrai-mark-color.svg" 512 "$color/vrai-mark-color@2x.png" >/dev/null
  node "$render" "$logos/vrai-mark-color-paper.svg" 256 "$color/vrai-mark-color-paper.png" >/dev/null
  node "$render" "$logos/vrai-mark-color-paper.svg" 512 "$color/vrai-mark-color-paper@2x.png" >/dev/null
  cat > "$color/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "vrai-mark-color.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "vrai-mark-color@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "vrai-mark-color-paper.png", "idiom" : "universal", "scale" : "1x" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "vrai-mark-color-paper@2x.png", "idiom" : "universal", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "original" }
}
JSON
  cat > "$assets/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  echo "marks: rendered VraiMark (template) and VraiMarkColor (light and dark)"
fi

check_icons
