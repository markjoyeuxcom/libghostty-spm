# Command Line Tools releases

This fork of [Lakr233/libghostty-spm](https://github.com/Lakr233/libghostty-spm)
exists for one reason: since 2.2.2026100701 the upstream package declares
`Localizable.xcstrings` as a processed resource, and SwiftPM compiles that with
`xcstringstool`, which ships only inside Xcode.app
([Lakr233/libghostty-spm#81](https://github.com/Lakr233/libghostty-spm/issues/81)).

The `clt` branch carries only `Script/clt` and the `CLT release` workflow. Each
upstream package tag `X.Y.Z` is republished as `X.Y.Z-clt`: the same sources,
with the catalog compiled into `<lang>.lproj/Localizable.strings` tables and
the three manifests pointing at them. The XCFramework stays upstream's release
asset; nothing is built with Zig here. Pin with

```swift
.package(url: "https://github.com/markjoyeuxcom/libghostty-spm.git", exact: "2.2.2026101003-clt")
```

The workflow runs daily and on demand, builds the result with the Command Line
Tools alone, runs upstream's localisation tests, then pushes the tag. When
upstream resolves #81 this fork can be deleted and consumers repointed.
