# Releasing LidLux

From the tested commit on `main`, create and push a new numeric version tag:

```sh
git tag -a v1.2.3 -m "LidLux 1.2.3"
git push origin v1.2.3
```

The Release workflow tests the app on an Apple Silicon `macos-15` runner, builds an ad-hoc signed app, and publishes a GitHub Release with the ZIP and SHA-256 checksum. The tag without `v` becomes the app version; the workflow run number becomes the build number. Use tags such as `v1.0` or `v1.2.3` (one to three numeric components).

Release notes combine `.github/release-notes-template.md` with GitHub's generated change notes. No Apple Developer account or signing secrets are required. Check the workflow result and the two release assets on GitHub after pushing.

## Homebrew cask

The cask in [n3wr1ch/homebrew-tap](https://github.com/n3wr1ch/homebrew-tap) updates itself: its `update-lidlux.yml` workflow checks the latest release every hour, verifies the checksum, updates `Casks/lidlux.rb`, runs `brew style`/`brew audit`, and commits. No token is needed. To update right after publishing a release:

```sh
gh workflow run update-lidlux.yml -R n3wr1ch/homebrew-tap
```

GitHub disables scheduled workflows in a repository with no activity for 60 days. If that happens, re-enable it from the tap's Actions tab (or run the command above).
