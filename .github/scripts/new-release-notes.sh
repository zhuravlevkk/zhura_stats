#!/usr/bin/env bash
set -euo pipefail

version=""
tag_name=""
output_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      version="${2:-}"
      shift 2
      ;;
    --tag-name)
      tag_name="${2:-}"
      shift 2
      ;;
    --output)
      output_path="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$version" ] || [ -z "$tag_name" ] || [ -z "$output_path" ]; then
  echo "Usage: $0 --version VERSION --tag-name TAG --output PATH" >&2
  exit 2
fi

repo="${GITHUB_REPOSITORY:-}"
if [ -z "$repo" ]; then
  echo "GITHUB_REPOSITORY is not set." >&2
  exit 1
fi

previous_tag="$(
  git tag --merged HEAD --sort=-v:refname |
    awk -v current="$tag_name" 'NF && $0 != current { print; exit }'
)"

if [ -n "$previous_tag" ]; then
  range="$previous_tag..HEAD"
else
  range="HEAD"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

commits_path="$tmp_dir/commits.md"
prs_jsonl="$tmp_dir/prs.jsonl"
: > "$commits_path"
: > "$prs_jsonl"

while IFS=$'\t' read -r sha short_sha subject; do
  [ -n "${sha:-}" ] || continue
  printf -- '- [%s](https://github.com/%s/commit/%s) %s\n' "$short_sha" "$repo" "$sha" "${subject:-$short_sha}" >> "$commits_path"

  if prs="$(gh api "repos/$repo/commits/$sha/pulls" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" 2>/dev/null)"; then
    printf '%s\n' "$prs" |
      jq -c '.[] | {number, title, html_url, body}' >> "$prs_jsonl"
  fi
done < <(git log "$range" --reverse --format='%H%x09%h%x09%s')

{
  printf '## NE Stats v%s\n\n' "$version"
  if [ -n "$previous_tag" ]; then
    printf 'Changes since [%s](https://github.com/%s/releases/tag/%s).\n\n' "$previous_tag" "$repo" "$previous_tag"
  else
    printf 'Initial release notes for this tag.\n\n'
  fi

  printf '### Merged pull requests\n\n'
  if [ -s "$prs_jsonl" ]; then
    jq -s 'unique_by(.number) | sort_by(.number)' "$prs_jsonl" |
      jq -r '.[] | @base64' |
      while IFS= read -r encoded; do
        pr="$(printf '%s' "$encoded" | base64 --decode)"
        number="$(printf '%s' "$pr" | jq -r '.number')"
        title="$(printf '%s' "$pr" | jq -r '.title // ""')"
        url="$(printf '%s' "$pr" | jq -r '.html_url')"
        body="$(printf '%s' "$pr" | jq -r '.body // ""')"

        printf '#### [#%s %s](%s)\n\n' "$number" "$title" "$url"
        if [ -n "$body" ]; then
          printf '%s\n\n' "$body"
        else
          printf '_No pull request description was provided._\n\n'
        fi
      done
  else
    printf '_No merged pull requests were associated with this release range._\n\n'
  fi

  if [ -s "$commits_path" ]; then
    printf '### Included commits\n\n'
    cat "$commits_path"
    printf '\n'
  fi
} > "$output_path"

echo "Release notes written to $output_path"
