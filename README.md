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
