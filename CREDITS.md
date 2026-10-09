# Credits

## Sprites

Spider-Man's sprites come from *The Amazing Spider-Man: Lethal Foes* (SNES, Japan release), from the
sheet on [The Spriters Resource](https://www.spriters-resource.com/snes/theamazingspidermanlethalfoesjpn/asset/471238).
The frames in `frames/` and `frames-custom/` are cut from that sheet, and some are edited.
Spider-Man and the original artwork are © Marvel.

## Sound effects

All sound effects are trimmed and level-matched versions of these files. They live in
`app/Resources/Sounds/`.

| App sound | Used for | Original | Author | License |
|---|---|---|---|---|
| `thwip.wav` | Web shot onto the top edge or a wall | `swish-6.wav` from [Swishes Sound Pack](https://opengameart.org/content/swishes-sound-pack) | artisticdude | [CC0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `fall.wav` | Falling to the bottom edge | `swish-9.wav` from [Swishes Sound Pack](https://opengameart.org/content/swishes-sound-pack) | artisticdude | [CC0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `release.wav` | Letting go of him | `drop_001.ogg` from [Interface Sounds](https://kenney.nl/assets/interface-sounds) | [Kenney](https://kenney.nl) | [CC0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `land.wav` | Landing on the bottom edge | `footstep_concrete_000.ogg` from [Impact Sounds](https://kenney.nl/assets/impact-sounds) | [Kenney](https://kenney.nl) | [CC0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `timerStart.m4a` | A timer or stopwatch starts | [tick-tock](https://freesound.org/people/foolboymedia/sounds/264498/) | foolboymedia | [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) |
| `timerDone.m4a` | Timer alarm | [96 marimba loop 2](https://freesound.org/people/thirsk/sounds/121094/) | thirsk | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |

CC0 doesn't require attribution, but thanks to those authors anyway. The two CC BY sounds require
the credit above; the tick-tock (BY-NC) also means it can't be used in a commercial version of the app.

## Font

Speech bubbles use [Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P) by CodeMan38,
under the SIL Open Font License (`app/Resources/PressStart2P-OFL.txt`).

## Charts

The analytics page (menu bar → Show Analytics) draws its chart with [Chart.js](https://www.chartjs.org)
4.4.1, under the MIT License (`app/Resources/Chart.js-LICENSE.txt`). The minified file is
`app/Resources/chart.umd.min.js`, unchanged from cdnjs.
