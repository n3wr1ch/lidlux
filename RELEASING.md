# Releasing LidLux

From the tested commit on `main`, create and push a new numeric version tag:

```sh
git tag -a v1.2.3 -m "LidLux 1.2.3"
git push origin v1.2.3
```

The Release workflow tests the app on an Apple Silicon `macos-15` runner, builds an ad-hoc signed app, and publishes a GitHub Release with the ZIP and SHA-256 checksum. The tag without `v` becomes the app version; the workflow run number becomes the build number. Use tags such as `v1.0` or `v1.2.3` (one to three numeric components).

Release notes combine `.github/release-notes-template.md` with GitHub's generated change notes. No Apple Developer account or signing secrets are required. Check the workflow result and the two release assets on GitHub after pushing.

## Update the Homebrew cask

After the release is published, update [n3wr1ch/homebrew-tap](https://github.com/n3wr1ch/homebrew-tap) `Casks/lidlux.rb` with the new version and the SHA-256 from the release asset, then push:

```sh
cd ../homebrew-tap
sed -i '' -e 's/version ".*"/version "1.2.3"/' -e 's/sha256 ".*"/sha256 "<sha256 from LidLux-1.2.3.zip.sha256>"/' Casks/lidlux.rb
brew style Casks/lidlux.rb && brew audit --cask --strict --online n3wr1ch/tap/lidlux
git commit -am "lidlux 1.2.3" && git push
```
