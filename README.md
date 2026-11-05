# AUR Update

Custom Action for keeping an AUR package's `PKGBUILD` current.

## Purpose

Checks upstream for a new version and, if one is found, bumps the package and pushes the change:

- **VCS packages** (a `PKGBUILD` with a `pkgver()` function): runs `makepkg -o` to re-derive `pkgver` from the latest commit, the same way a user's build would.
- **Release packages** (a static `pkgver=`): parses the `source=` array for a `github.com/<owner>/<repo>/archive/.../tags/<prefix>${pkgver}...` URL, queries the GitHub API for the latest release, and updates `pkgver` and checksums (via `updpkgsums`) if it changed. The new `pkgver` is the tag minus the prefix and any leftover non-digit characters, so a tag-style change upstream (`v3.2` → `v.3.3`) still yields `3.3`; a tag that doesn't yield a valid `pkgver` fails the run. If the upstream tag can't be rebuilt from `pkgver` alone, keep it in a `_tag=` line and use `${_tag}` in the source URL; the action sets it to the literal tag on every bump.

Either way, `.SRCINFO` is regenerated, and if anything changed, it's committed and pushed with `git`. Sets an `updated` output (`true`/`false`) so callers can conditionally run a publish step afterward.

## Usage

```yaml
- id: update
  uses: its-me/action.aur.update@v0
  with:
    path: release
    github-token: ${{ secrets.GITHUB_TOKEN }}

- if: steps.update.outputs.updated == 'true'
  uses: its-me/action.aur.publish@v0
  with:
    path: release
    ssh-key: ${{ secrets.AUR_SSH_KEY }}
```

## License

[MIT](LICENSE)
