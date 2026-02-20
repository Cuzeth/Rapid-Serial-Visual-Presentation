#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/cuz/GitHub/Rapid-Serial-Visual-Presentation"
DOCS_DIR="$ROOT/Strobe.doccarchive/data/documentation/strobe"
OUT_DIR="$ROOT/wiki-md"

mkdir -p "$OUT_DIR"

render_overview() {
  local file="$1"
  jq -r '
    . as $doc
    |
    [
      .primaryContentSections[]? | select(.kind=="content") | .content[]? |
      if .type=="heading" then
        "## " + .text + "\n"
      elif .type=="paragraph" then
        ([
          .inlineContent[]? |
          if .type=="text" then .text
          elif .type=="codeVoice" then "`" + .code + "`"
          elif .type=="reference" then
            "`" + (($doc.references[.identifier].title // .identifier) | tostring) + "`"
          else ""
          end
        ] | join("")) + "\n"
      else empty end
    ] | join("\n")
  ' "$file"
}

render_topics() {
  local file="$1"
  jq -r '
    . as $doc
    | def inline_text($arr):
        [
          $arr[]? |
          if .type=="text" then .text
          elif .type=="codeVoice" then "`" + .code + "`"
          elif .type=="reference" then "`" + (($doc.references[.identifier].title // .identifier) | tostring) + "`"
          else ""
          end
        ] | join("") | gsub("\\n"; " ");
      def signature($r):
        (((($r.fragments // []) | map(.text) | join("")) // "") | gsub("\\n"; " "));
    [
        .topicSections[]?
        | select((.identifiers // []) | length > 0)
        | select(.title != "Default Implementations")
        | . as $section
        | (
            $section.identifiers
            | map(
                ($doc.references[.] // empty) as $r
                | (signature($r)) as $sig
                | (($r.title // "") | tostring) as $title
                | (if ($sig | length) > 0 then $sig else $title end) as $name
                | inline_text($r.abstract // []) as $abs
                | if ($name | length) > 0 then
                    "- `" + $name + "`" + (if ($abs | length) > 0 then " - " + $abs else "" end)
                  else
                    empty
                  end
              )
          ) as $entries
        | select(($entries | length) > 0)
        | "### " + $section.title,
          ($entries | join("\n")),
          ""
      ]
    | join("\n")
  ' "$file"
}

# Build symbol pages
for file in "$DOCS_DIR"/*.json; do
  slug="$(basename "$file" .json)"
  title="$(jq -r '.metadata.title' "$file")"
  role="$(jq -r '.metadata.roleHeading // .metadata.symbolKind // "Symbol"' "$file")"
  abstract="$(jq -r '. as $doc | ([.abstract[]? | if .type=="text" then .text elif .type=="codeVoice" then "`" + .code + "`" elif .type=="reference" then "`" + (($doc.references[.identifier].title // .identifier) | tostring) + "`" else "" end] | join(""))' "$file")"
  path="$(jq -r '.variants[0].paths[0] // ""' "$file")"

  out="$OUT_DIR/$title.md"

  {
    echo "# $title"
    echo
    echo "- **Type:** $role"
    echo "- **Module:** Strobe"
    if [[ -n "$path" ]]; then
      echo "- **DocC Path:** \`$path\`"
    fi
    echo

    if [[ -n "$abstract" ]]; then
      echo "$abstract"
      echo
    fi

    overview="$(render_overview "$file")"
    if [[ -n "${overview// /}" ]]; then
      echo "$overview"
      echo
    fi

    topics="$(render_topics "$file")"
    if [[ -n "${topics// /}" ]]; then
      echo "## API"
      echo
      echo "$topics"
    fi
  } > "$out"
done

# Build Home.md from module page topic sections
module_file="$ROOT/Strobe.doccarchive/data/documentation/strobe.json"
{
  echo "# Strobe Wiki"
  echo
  echo "Documentation exported from \`Strobe.doccarchive\` for easy copy/paste into GitHub Wiki."
  echo

  jq -r '
    . as $doc
    | .topicSections[]? |
      select((.identifiers // []) | length > 0) |
      "## " + .title,
      (
        [
          .identifiers[] as $id |
          ($doc.references[$id] // empty) as $r |
          ("- [" + $r.title + "](" + $r.title + ")"
            + (if (($r.abstract // []) | length) > 0 then
                 " - " + ([
                   $r.abstract[]? |
                   if .type=="text" then .text
                   elif .type=="codeVoice" then "`" + .code + "`"
                   elif .type=="reference" then "`" + (($doc.references[.identifier].title // .identifier) | tostring) + "`"
                   else ""
                   end
                 ] | join("") | gsub("\\n"; " "))
               else ""
               end)
          )
        ] | join("\n")
      ),
      ""
  ' "$module_file"
} > "$OUT_DIR/Home.md"

# Build _Sidebar.md
{
  echo "[[Home]]"
  echo
  jq -r '
    . as $doc
    | .topicSections[]? |
      select((.identifiers // []) | length > 0) |
      "### " + .title,
      (
        [
          .identifiers[] as $id |
          ($doc.references[$id] // empty) as $r |
          "- [[" + $r.title + "]]"
        ] | join("\n")
      ),
      ""
  ' "$module_file"
} > "$OUT_DIR/_Sidebar.md"

# Manifest
{
  echo "Generated on: $(date -u +"%Y-%m-%d %H:%M:%SZ")"
  echo "Source: $ROOT/Strobe.doccarchive"
  echo "Pages:"
  find "$OUT_DIR" -maxdepth 1 -type f -name '*.md' -exec basename {} \; | sort
} > "$OUT_DIR/README.md"

echo "Generated wiki markdown in: $OUT_DIR"
