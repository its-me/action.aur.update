#!/bin/bash
set -e

cd "${GITHUB_WORKSPACE}/${PKG_PATH}"

git config --global --add safe.directory "${GITHUB_WORKSPACE}"
git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"

if grep -qE '^pkgver\s*\(\s*\)' PKGBUILD; then
  echo "::group::Refresh VCS pkgver"
  chown -R builder .
  su builder -c "makepkg -o --noconfirm --nocheck"
  echo "::endgroup::"
else
  echo "::group::Check for a new release"
  _current_pkgver=$(grep '^pkgver=' PKGBUILD | cut -d= -f2)

  # Use the fully-expanded .SRCINFO rather than grepping the raw PKGBUILD,
  # since source= entries commonly reference other variables (e.g.
  # ${_pkgname}), span multiple lines, or are arch-specific
  # (source_x86_64=, ...) -- none of which a literal regex on PKGBUILD text
  # can resolve.
  chown -R builder .
  _srcinfo=$(su builder -c "makepkg --printsrcinfo")

  _src_line=$(printf '%s\n' "$_srcinfo" | grep -E 'github\.com/[^/[:space:]]+/[^/[:space:]]+/(archive|releases/download)/' | grep -F "$_current_pkgver" | head -n1)
  if [ -z "$_src_line" ]; then
    echo "::error::Could not find a github.com source entry referencing the current pkgver"
    exit 1
  fi

  _owner_repo=$(echo "$_src_line" | sed -nE 's#.*github\.com/([^/]+/[^/]+)/(archive|releases/download)/.*#\1#p')

  if echo "$_src_line" | grep -q '/releases/download/'; then
    _tag_segment=$(echo "$_src_line" | sed -nE 's#.*/releases/download/([^/]+)/.*#\1#p')
  else
    _tag_segment=$(echo "$_src_line" | sed -nE 's#.*/archive/(refs/tags/)?([^/]+)\.(tar\.gz|tar\.xz|tar\.bz2|tar\.zst|tgz|tbz2|zip).*#\2#p')
  fi
  _prefix=$(echo "$_tag_segment" | sed -nE "s#^(.*)${_current_pkgver}\$#\1#p")

  if ! _latest_tag=$(gh api "repos/${_owner_repo}/releases/latest" --jq '.tag_name' 2>/dev/null); then
    # Some upstreams only publish git tags, never GitHub Releases.
    _latest_tag=$(gh api "repos/${_owner_repo}/tags" --jq '.[0].name' 2>/dev/null) || _latest_tag=""
  fi
  if [ -z "$_latest_tag" ]; then
    echo "::error::Could not determine the latest release or tag for ${_owner_repo}"
    exit 1
  fi

  _new_pkgver="${_latest_tag#"$_prefix"}"

  if [ "$_new_pkgver" = "$_current_pkgver" ]; then
    echo "Already up to date (${_current_pkgver})"
    echo "::endgroup::"
    echo "updated=false" >> "$GITHUB_OUTPUT"
    exit 0
  fi

  echo "New release: ${_current_pkgver} -> ${_new_pkgver}"
  sed -i "s/^pkgver=.*/pkgver=${_new_pkgver}/" PKGBUILD
  chown -R builder .
  su builder -c "updpkgsums PKGBUILD"
  echo "::endgroup::"
fi

if git diff --quiet -- PKGBUILD; then
  echo "No changes to commit"
  echo "updated=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "::group::Commit and push"
_ver=$(grep '^pkgver=' PKGBUILD | cut -d= -f2)
_rel=$(grep '^pkgrel=' PKGBUILD | cut -d= -f2)
git add PKGBUILD
git commit -m "${COMMIT_MSG:-update to ${_ver}-${_rel}}"
git push
echo "::endgroup::"

echo "updated=true" >> "$GITHUB_OUTPUT"
