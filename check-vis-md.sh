#!/usr/bin/env bash
set -euo pipefail

# Glassbox safety-net hook — detects missing or stale .vis.md files
# and sends a follow-up message to the agent to create/update them.

SKIP_PATTERN='(\.vis\.md$|\.vis/|node_modules/|venv/|__pycache__/|\.git/|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|poetry\.lock|Cargo\.lock|Gemfile\.lock|composer\.lock|\.gitignore|\.gitattributes|\.dockerignore|\.env|\.editorconfig|tsconfig\.json|\.eslintrc|\.prettierrc|\.babelrc|\.stylelintrc|\.browserslistrc|\.nvmrc|\.ruby-version|\.python-version|\.tool-versions|Makefile|Dockerfile|LICENSE|\.md$|\.txt$|\.csv$|\.json$|\.yaml$|\.yml$|\.toml$|\.ini$|\.cfg$|\.conf$|\.xml$|\.svg$|\.png$|\.jpg$|\.jpeg$|\.gif$|\.ico$|\.woff|\.ttf$|\.eot$|\.mp4$|\.mp3$|\.pdf$)'

cat > /dev/null

if ! git rev-parse --show-toplevel > /dev/null 2>&1; then
  echo '{}'
  exit 0
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel)
VIS_DIR="$PROJECT_ROOT/.vis"

changed_files=$(
  {
    git diff --name-only HEAD 2>/dev/null || true
    git diff --name-only --cached 2>/dev/null || true
    git ls-files --others --exclude-standard 2>/dev/null || true
  } | sort -u
)

if [ -z "$changed_files" ]; then
  echo '{}'
  exit 0
fi

missing=()
stale=()

while IFS= read -r file; do
  if echo "$file" | grep -qE "$SKIP_PATTERN"; then
    continue
  fi

  if [ ! -f "$PROJECT_ROOT/$file" ]; then
    continue
  fi

  vis_file="$VIS_DIR/${file}.vis.md"

  if [ ! -f "$vis_file" ]; then
    missing+=("$file")
    continue
  fi

  if [ "$PROJECT_ROOT/$file" -nt "$vis_file" ]; then
    current_hash=$(md5 -q "$PROJECT_ROOT/$file" 2>/dev/null || md5sum "$PROJECT_ROOT/$file" | awk '{print $1}')
    stored_hash=$(sed -n 's/.*<!-- source-hash: \([a-f0-9]*\) -->.*/\1/p' "$vis_file" 2>/dev/null || echo "")

    if [ "$current_hash" != "$stored_hash" ]; then
      stale+=("$file")
    fi
  fi
done <<< "$changed_files"

if [ ${#missing[@]} -eq 0 ] && [ ${#stale[@]} -eq 0 ]; then
  echo '{}'
  exit 0
fi

msg="Some .vis.md files need attention. Follow the glassbox rule to create or update them.\n\n"

if [ ${#missing[@]} -gt 0 ]; then
  msg+="MISSING .vis.md (create these):\n"
  for f in "${missing[@]}"; do
    msg+="  - $f -> .vis/${f}.vis.md\n"
  done
fi

if [ ${#stale[@]} -gt 0 ]; then
  msg+="STALE .vis.md (source hash mismatch — update these):\n"
  for f in "${stale[@]}"; do
    msg+="  - $f -> .vis/${f}.vis.md\n"
  done
fi

json_msg=$(printf '%b' "$msg" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

printf '{"followup_message": %s}' "$json_msg"
exit 0
