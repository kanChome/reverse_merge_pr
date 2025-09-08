#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  echo "Usage: $0 owner/repo"
  exit 1
fi

log() { echo "[$(date +'%F %T')] $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found"; exit 1; }
}
require_cmd git
require_cmd gh

# base..head の差分が下流(base)に存在するか判定
need_pr() {
  local base="$1" head="$2"
  git rev-list --left-right --count "origin/${base}...origin/${head}" \
    | awk '{print ($1 > 0) ? "yes" : "no"}'
}

# 既存PR番号を取得（無ければ空文字）
find_open_pr() {
  local base="$1" head="$2"
  gh pr list -R "$REPO" --base "$base" --head "$head" --state open \
    --json number --jq '.[0].number' 2>/dev/null || true
}

# PR作成（なければ）＋ 自動マージを有効化
ensure_pr_and_automerge() {
  local base="$1" head="$2" title="$3" body="$4"
  local prnum
  prnum="$(find_open_pr "$base" "$head" || true)"

  if [[ -z "$prnum" ]]; then
    local url
    url="$(gh pr create -R "$REPO" --base "$base" --head "$head" \
             --title "$title" --body "$body")"
    prnum="$(sed -E 's#.*/pull/([0-9]+).*#\1#' <<<"$url")"
    log "Created PR #$prnum ($head -> $base): $url"
  else
    log "Reuse existing PR #$prnum ($head -> $base)"
  fi

  gh pr merge -R "$REPO" "$prnum" --auto --merge
  log "Enabled auto-merge (merge commit) for PR #$prnum"
}

main() {
  git fetch --all --prune

  # 1) production -> staging
  if [[ "$(need_pr staging production)" == "yes" ]]; then
    log "Diff detected: production -> staging"
    ensure_pr_and_automerge "staging" "production" \
      "Reverse merge: production → staging" \
      "自動生成PR: productionの最新をstagingに取り込みます。"
  else
    log "No diff: production -> staging"
  fi

  # 2) staging -> development
  if [[ "$(need_pr development staging)" == "yes" ]]; then
    log "Diff detected: staging -> development"
    ensure_pr_and_automerge "development" "staging" \
      "Reverse merge: staging → development" \
      "自動生成PR: stagingの最新をdevelopmentに取り込みます。"
  else
    log "No diff: staging -> development"
  fi
}

main "$@"