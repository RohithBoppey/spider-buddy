# Spider Buddy

A macOS desktop pet: a pixel-art Spider-Man that floats above your apps and hangs from
the top of the screen on a web. Personal project; the sprites are Marvel's, so don't distribute.

## Run it

Needs macOS 13+ and Swift (the Xcode Command Line Tools are enough: `xcode-select --install`).

```sh
cd app
./build.sh                    # compiles and assembles app/build/SpiderBuddy.app
open build/SpiderBuddy.app    # quit from the 🕷️ menu-bar icon
```

Rebuild after changing Swift code or anything in `frames-custom/`. If an old copy is running,
quit it first (or `pkill -x SpiderBuddy`).

## Layout

| Path | What |
|---|---|
| `app/` | The Swift app (Swift Package, AppKit). `build.sh` bundles it with the sprites. |
| `frames/` | The original 212 sprite frames (trimmed PNGs, no shared anchor). |
| `frames-custom/` | Frames the app uses, one folder per pose: `top-hang`, `wall-ready`, `wall-crawl`, `bottom-crawl`, `pickup`. Files starting with `_` are previews and are not bundled. |
| `frames-custom/top-hang/draw_hang.py` | Generates the hanging frames (`hang_00`–`hang_04`) and their previews. |
| `frames-custom/bottom-crawl/prepare_crawl.py` | Splits frame 095, writes `anchors.json` (head-fixed alignment) and `_preview.gif`. |
| `frames-custom/wall-crawl/prepare_wall.py` | Builds the wall ready frame (018 with feet planted), writes wall `anchors.json` and `_preview.gif`. |
| `sprites-raw/` | Source sprite sheet and pose reference. |

## Regenerate the hanging frames

```sh
python3 frames-custom/top-hang/draw_hang.py   # needs Pillow: pip3 install pillow
```

Writes `hang_00`–`hang_04.png`, `_preview.png` (next to original frames) and `_preview.gif`
(the loop as the app plays it).
