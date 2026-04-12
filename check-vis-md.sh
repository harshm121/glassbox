#!/usr/bin/env bash
set -euo pipefail

# Glassbox safety-net hook — detects missing, stale, or orphaned .vis.md files
# and sends a follow-up message to the agent to create/update/delete them.
#
# Usage:
#   bash check-vis-md.sh            # Cursor hook mode (default): outputs JSON followup
#   bash check-vis-md.sh --ci       # CI mode: prints human-readable report, exits 1 on violations

CI_MODE=false
if [[ "${1:-}" == "--ci" ]]; then
  CI_MODE=true
  shift
fi

SKIP_PATTERN='(\.vis\.md$|\.vis/|node_modules/|venv/|__pycache__/|\.git/|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|poetry\.lock|Cargo\.lock|Gemfile\.lock|composer\.lock|\.gitignore|\.gitattributes|\.dockerignore|\.env|\.editorconfig|tsconfig\.json|\.eslintrc|\.prettierrc|\.babelrc|\.stylelintrc|\.browserslistrc|\.nvmrc|\.ruby-version|\.python-version|\.tool-versions|Makefile|Dockerfile|LICENSE|\.md$|\.txt$|\.csv$|\.json$|\.yaml$|\.yml$|\.toml$|\.ini$|\.cfg$|\.conf$|\.xml$|\.svg$|\.png$|\.jpg$|\.jpeg$|\.gif$|\.ico$|\.woff|\.ttf$|\.eot$|\.mp4$|\.mp3$|\.pdf$)'

if [[ "$CI_MODE" == false ]]; then
  cat > /dev/null
fi

if ! git rev-parse --show-toplevel > /dev/null 2>&1; then
  if [[ "$CI_MODE" == true ]]; then
    echo "Not a git repository, skipping."
    exit 0
  fi
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

missing=()
stale=()
orphaned=()

# --- Detect orphaned .vis.md files whose source no longer exists ---
if [ -d "$VIS_DIR" ]; then
  while IFS= read -r vis_file; do
    [ -z "$vis_file" ] && continue
    rel_vis="${vis_file#$VIS_DIR/}"
    source_rel="${rel_vis%.vis.md}"
    if [ ! -f "$PROJECT_ROOT/$source_rel" ]; then
      orphaned+=("$source_rel")
    fi
  done < <(find "$VIS_DIR" -name '*.vis.md' -type f 2>/dev/null)
fi

# --- Detect missing and stale .vis.md for changed code files ---
if [ -n "$changed_files" ]; then
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
fi

# --- Detect stale project index ---
index_stale=false
if [ -d "$VIS_DIR" ]; then
  index_file="$VIS_DIR/_index.vis.md"
  if [ ! -f "$index_file" ]; then
    vis_count=$(find "$VIS_DIR" -name '*.vis.md' -not -name '_index.vis.md' -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$vis_count" -gt 0 ]; then
      index_stale=true
    fi
  elif [ ${#missing[@]} -gt 0 ] || [ ${#stale[@]} -gt 0 ] || [ ${#orphaned[@]} -gt 0 ]; then
    index_stale=true
  fi
fi

if [ ${#missing[@]} -eq 0 ] && [ ${#stale[@]} -eq 0 ] && [ ${#orphaned[@]} -eq 0 ] && [[ "$index_stale" == false ]]; then
  if [[ "$CI_MODE" == true ]]; then
    echo "Glassbox: all .vis.md files are up to date."
    exit 0
  fi
  echo '{}'
  exit 0
fi

# --- Build report message ---
msg="Some .vis.md files need attention. Follow the glassbox rule to create, update, or delete them.\n\n"

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

if [ ${#orphaned[@]} -gt 0 ]; then
  msg+="ORPHANED .vis.md (source file deleted — remove these):\n"
  for f in "${orphaned[@]}"; do
    msg+="  - .vis/${f}.vis.md (source $f no longer exists)\n"
  done
fi

if [[ "$index_stale" == true ]]; then
  msg+="INDEX STALE: .vis/_index.vis.md needs to be created or updated to reflect the latest changes.\n"
fi

# --- CI mode: human-readable output + non-zero exit ---
if [[ "$CI_MODE" == true ]]; then
  printf '%b' "$msg"
  index_count=0
  [[ "$index_stale" == true ]] && index_count=1
  total=$(( ${#missing[@]} + ${#stale[@]} + ${#orphaned[@]} + index_count ))
  echo ""
  echo "Glassbox: $total violation(s) found."
  exit 1
fi

# --- Cursor hook mode: JSON followup message ---
json_msg=$(printf '%b' "$msg" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

printf '{"followup_message": %s}' "$json_msg"
exit 0
