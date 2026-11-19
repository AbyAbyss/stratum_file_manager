# Developing Stratum

## Keeping folder permissions between rebuilds

A Debug build is signed ad-hoc by default. macOS can't recognise an ad-hoc app as the same app
after a rebuild, so it asks for Downloads, Documents and Desktop access again every time.

Sign your local builds with a certificate from your own Keychain instead. Create
`Config/Local.xcconfig` (git-ignored, so it never reaches CI):

```
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = <the SHA-1 from `security find-identity -p codesigning`>
DEVELOPMENT_TEAM = <your team ID>
```

Then run `xcodegen generate` and rebuild. Without that file, builds are ad-hoc signed as before.
