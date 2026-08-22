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
  _src_line=$(grep -m1 '^source=' PKGBUILD)
  _owner_repo=$(echo "$_src_line" | sed -nE 's#.*github\.com/([^/]+/[^/]+)/archive.*#\1#p')
  if [ -z "$_owner_repo" ]; then
    echo "::error::Could not determine a github.com owner/repo from the source= line"
    exit 1
  fi

  _prefix=$(echo "$_src_line" | sed -nE 's#.*/([^/]*)\$\{pkgver\}.*#\1#p')
  _current_pkgver=$(grep '^pkgver=' PKGBUILD | cut -d= -f2)

  _latest_tag=$(gh api "repos/${_owner_repo}/releases/latest" --jq '.tag_name')
  if [ -z "$_latest_tag" ]; then
    echo "::error::Could not determine the latest release for ${_owner_repo}"
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

echo "::group::Regenerate .SRCINFO"
chown -R builder .
su builder -c "makepkg --printsrcinfo" > .SRCINFO
echo "::endgroup::"

if git diff --quiet -- PKGBUILD .SRCINFO; then
  echo "No changes to commit"
  echo "updated=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "::group::Commit and push"
_ver=$(grep '^pkgver=' PKGBUILD | cut -d= -f2)
_rel=$(grep '^pkgrel=' PKGBUILD | cut -d= -f2)
git add PKGBUILD .SRCINFO
git commit -m "${COMMIT_MSG:-update to ${_ver}-${_rel}}"
git push
echo "::endgroup::"

echo "updated=true" >> "$GITHUB_OUTPUT"
