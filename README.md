# Maybe

Maybe is a 100% local iOS 26+ library for the things that catch your attention and the ideas they become.

## Product loop

1. Save a photo, link, note, or file.
2. Capture *what caught you?*
3. Connect saved things to an idea through **Inspired by**.
4. Rediscover older saves with **Again** and **Maybe?**.

There is no account, backend, analytics SDK, cloud database, or remote AI service. Structured metadata is stored with SwiftData. Imported media is written under Application Support and referenced by relative path. Export creates a single `.maybe` archive that can be imported manually.

The `MaybeShare` extension accepts photos, links, text, and files from the system Share sheet. It queues them inside the local Maybe App Group, optionally associates an existing Idea, and imports them into Inbox the next time the app opens.

## Build

Open `Maybe.xcodeproj`, select the `Maybe` scheme, and run on an iOS 26 simulator.

The CI workflow builds and runs unit tests on GitHub's `macos-26` runner.

Sample content is available only to CI and UI review launches through the
`--use-sample-data` argument. Normal installs start with an empty local library.
