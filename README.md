# Xpeet

iOS app (SwiftUI, iOS 17+), project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Setup

```sh
brew install xcodegen
xcodegen generate
open Xpeet.xcodeproj
```

Run `xcodegen generate` again whenever you add/remove files or change `project.yml`.

## Structure

```
Xpeet/
  App/         entry point, root view, app-wide state
  Core/        shared code (networking, extensions)
  Features/    one folder per feature (View + ViewModel)
  Resources/   assets
XpeetTests/    unit tests
```

## AI-native SDLC

Development runs through Claude Code locally: intent -> spec -> plan -> build -> verify -> review. See [docs/ai-sdlc.md](docs/ai-sdlc.md).
One-time: `brew install swiftlint && git config core.hooksPath .githooks`.
