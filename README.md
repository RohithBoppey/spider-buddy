<div align="center">

# 🕷️ Spider Buddy

**A pixel-art Spider-Man that lives on your Mac's desktop.**<br>
He hangs from the menu bar on a web, crawls along the edges of your screen and drops the odd word of encouragement.

<img src="assets/spiderman-demo.gif" alt="Spider Buddy swinging around a macOS desktop" width="720">

<sub>Personal project. The sprites are Marvel's, so don't distribute.</sub>

</div>

---

## ✨ What he does

- 🕸️ **Hangs from the top** of your screen on a web, floating above every app
- 🧗 **Crawls** along the bottom and up the walls, then rests a while
- 💬 **Speech bubbles** with little nudges (*Drink some water!*) in a pixel font
- 🖐️ **Pick him up** and drop him somewhere else, or send him to any edge from the 🕷️ menu
- 🖥️ **Multi-display aware**: follows your active display, or stays put
- 🙈 **Hides during fullscreen** apps so he never gets in the way
- ⚙️ **Settings** for size, energy, web length, bubble frequency and font
- 🔄 **Updates himself** through [Sparkle](https://sparkle-project.org)

## 🚀 Install

Paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/RohithBoppey/spider-buddy/main/install.sh | bash
```

It downloads the latest release, installs it to `/Applications` (or `~/Applications` if you're not
an admin) and launches it. Run it again any
time to reinstall. Look for 🕷️ in the menu bar for settings and to quit.

<details>
<summary>💿 <b>Prefer the .dmg?</b></summary>
<br>

1. Download the latest `SpiderBuddy-<version>.dmg` from [Releases](https://github.com/RohithBoppey/spider-buddy/releases/latest).
2. Open it and drag **Spider Buddy** onto **Applications**.
3. The app isn't notarized, so the first launch is blocked: right-click it in Applications →
   **Open** → **Open** (or allow it under *System Settings → Privacy & Security*).

</details>

> [!NOTE]
> Needs macOS 13 (Ventura) or later.

---

## 🧑‍💻 Development

<details>
<summary>🛠️ <b>Build & run</b></summary>
<br>

Needs macOS 13+ and Swift (the Xcode Command Line Tools are enough: `xcode-select --install`).

```sh
cd app
./build.sh                    # compiles and assembles app/build/SpiderBuddy.app
open build/SpiderBuddy.app    # quit from the 🕷️ menu-bar icon
```

Rebuild after changing Swift code or anything in `frames-custom/`. If an old copy is running,
quit it first (or `pkill -x SpiderBuddy`).

</details>

<details>
<summary>📦 <b>Packaging a .dmg</b></summary>
<br>

To make an installable disk image (app + Applications shortcut):

```sh
cd app
./package.sh                  # builds, then writes app/dist/SpiderBuddy-<version>.dmg
```

</details>

<details>
<summary>🚢 <b>Releasing an update</b></summary>
<br>

Installed copies update themselves through [Sparkle](https://sparkle-project.org): they read
`appcast.xml` (this repo) and download the `.dmg` from GitHub Releases. `install.sh` also
installs whatever the latest GitHub Release is.

```sh
cd app
./release.sh 1.1.0 "What's new"   # sets the version, builds, packages, signs, adds it to appcast.xml
```

Then run the two commands it prints: `gh release create …` first (uploads the .dmg), then commit and
push `appcast.xml` (announces it). The update signing key lives in your login Keychain
(account `spider-buddy`); back it up with
`app/.tools/sparkle/bin/generate_keys --account spider-buddy -x <file>`. Without it,
installed copies can never be updated again.

</details>

<details>
<summary>🗂️ <b>Project layout</b></summary>
<br>

| Path | What |
|---|---|
| `app/` | The Swift app (Swift Package, AppKit). `build.sh` bundles it with the sprites. |
| `install.sh` | The one-line installer: fetches the latest release's `.dmg` and installs it. |
| `assets/` | Images for this README. |
| `frames/` | The original 212 sprite frames (trimmed PNGs, no shared anchor). |
| `frames-custom/` | Frames the app uses, one folder per pose: `top-hang`, `wall-ready`, `wall-crawl`, `bottom-crawl`, `pickup`. Files starting with `_` are previews and are not bundled. |
| `frames-custom/top-hang/draw_hang.py` | Generates the hanging frames (`hang_00`–`hang_04`) and their previews. |
| `frames-custom/bottom-crawl/prepare_crawl.py` | Splits frame 095, writes `anchors.json` (head-fixed alignment) and `_preview.gif`. |
| `frames-custom/wall-crawl/prepare_wall.py` | Builds the wall ready frame (018 with feet planted), writes wall `anchors.json` and `_preview.gif`. |
| `app/Resources/lines.txt` | What he says in speech bubbles, one line each (`#` = comment). Rebuild after editing. |
| `app/Resources/PressStart2P-*` | Pixel font for the bubbles and its SIL Open Font License. |
| `sprites-raw/` | Source sprite sheet and pose reference. |

</details>

<details>
<summary>🎨 <b>Regenerating the hanging frames</b></summary>
<br>

```sh
python3 frames-custom/top-hang/draw_hang.py   # needs Pillow: pip3 install pillow
```

Writes `hang_00`–`hang_04.png`, `_preview.png` (next to original frames) and `_preview.gif`
(the loop as the app plays it).

</details>

<div align="center">
<br>
<sub>Made with 🕸️ and Swift</sub>
</div>
