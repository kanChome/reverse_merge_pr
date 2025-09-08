#!/usr/bin/env bash
set -euo pipefail

REPO=""
DRY_RUN="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    -*)
      echo "未知のオプションです: $1"
      echo "Usage: $0 owner/repo [--dry-run]"
      exit 1
      ;;
    *)
      if [[ -z "$REPO" ]]; then
        REPO="$1"
      else
        echo "Usage: $0 owner/repo [--dry-run]"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Usage: $0 owner/repo [--dry-run]"
  exit 1
fi

log() { echo "[$(date +'%F %T')] $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found"; exit 1; }
}
require_cmd git
require_cmd gh

# base..head の差分が 下流（base）側に存在するか判定
need_pr() {
  local base="$1" head="$2"
  git rev-list --left-right --count "origin/${base}...origin/${head}" \
    | awk '{print ($1 > 0) ? "yes" : "no"}'
}

# 既存オープンPRがあれば PR番号を返す。なければ空文字。
find_open_pr() {
  local base="$1" head="$2"
  gh pr list -R "$REPO" --base "$base" --head "$head" --state open \
    --json number --jq '.[0].number' 2>/dev/null || true
}

# PRを作成（必要なら）。URLを出力。
create_pr_if_needed() {
  local base="$1" head="$2" title="$3" body="$4"

  # 差分がないならスキップ
  if [[ "$(need_pr "$base" "$head")" != "yes" ]]; then
    log "No diff: ${head} -> ${base}（PR不要）"
    return 0
  fi

  # 既存PRがあれば再利用
  local prnum
  prnum="$(find_open_pr "$base" "$head" || true)"
  if [[ -n "$prnum" ]]; then
    local url="https://github.com/${REPO}/pull/${prnum}"
    log "Reuse existing PR #$prnum (${head} -> ${base}): ${url}"
    echo "$url"
    return 0
  fi

  # 新規作成
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY_RUN] would create PR: ${head} -> ${base}"
    echo "(dry-run) https://github.com/${REPO}/pull/NEW"
    return 0
  fi

  local url
  url="$(gh pr create -R "$REPO" --base "$base" --head "$head" \
           --title "$title" --body "$body")"
  log "Created PR (${head} -> ${base}): ${url}"
  echo "$url"
}

main() {
  git fetch --all --prune

  # production -> staging
  create_pr_if_needed "staging" "production" \
    "Reverse merge: production → staging" \
    "自動生成PR: productionの最新をstagingに取り込みます。"

  # staging -> development
  create_pr_if_needed "development" "staging" \
    "Reverse merge: staging → development" \
    "自動生成PR: stagingの最新をdevelopmentに取り込みます。"
}

main
