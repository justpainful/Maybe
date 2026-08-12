# Maybe

Maybe is a 100% local iOS 26+ library for the things that catch your attention and the ideas they become.

## Product loop

1. Save a photo, link, note, or file.
2. Capture *what caught you?*
3. Connect saved things to an idea through **Inspired by**.
4. Rediscover older saves with **Again** and **Maybe?**.

An exported `.maybe` package holds `library.json`, the media, and an
`index.html` you can open in any browser with no app and no network. That page
inverts the app: months later the sentence you wrote matters more than the
picture, so what you said leads and the photo supports it. The library travels
inside the page as inlined JSON because browsers refuse to fetch sibling files
from `file://` — only the photos are read from the folder beside it.

There is no account, backend, analytics SDK, cloud database, or remote AI service. Structured metadata is stored with SwiftData. Imported media is written under Application Support and referenced by relative path. Export creates a single `.maybe` archive that can be imported manually.

The `MaybeShare` extension accepts photos, links, text, and files from the system Share sheet. It queues them inside the local Maybe App Group, optionally associates an existing Idea, and imports them into Inbox the next time the app opens.

## Interface rules

- **A saved thing only ever shows its own content.** A photo shows the photo; a
  note shows its text; a link shows its domain; a file shows its name. The app
  never draws artwork to stand in for something it does not have.
- **Nothing is cropped to fit a grid cell.** Every attachment records its real
  pixel size, and tiles take their photo's proportions in a two-column masonry.
  Detail and resurfacing views fit the photo rather than filling the frame.
- **Liquid Glass is for chrome, keycaps are for controls, cards are quiet.**
  Glass belongs to the tab bar and floating badges, keycaps to buttons, filters
  and tags, and content sits on the flat cream canvas.
- **A section with nothing to show does not render.** Empty rails, placeholder
  cards and explanatory subtitles are not part of the layout.

## Build

Open `Maybe.xcodeproj`, select the `Maybe` scheme, and run on an iOS 26 simulator.

The CI workflow builds and runs unit tests on GitHub's `macos-26` runner.

Sample content is available only to CI and UI review launches through the
`--use-sample-data` argument. Normal installs start with an empty local library.
The sample library writes real JPEGs of several aspect ratios through the same
media pipeline a user's photos take, so review screenshots show real layout.

Each CI run screenshots every screen on an iPhone 17 simulator and uploads them
as the `maybe-ios-ci` artifact. Screens are reached with launch arguments:
`--show-inbox`, `--show-ideas`, `--show-idea-detail`, `--show-detail`,
`--show-search`, `--show-add`, `--show-edit`, `--show-new-idea`,
`--show-surprise`, `--show-settings`, and `--qa-composer-photos` to open the
composer with photos already chosen.
