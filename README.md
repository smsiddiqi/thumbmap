# ThumbMap — thumb-button remapper for the Anker A7851 on macOS

## What it does (default configuration)

| Physical button            | Quick click                         | Press and hold (≥ 300 ms)                    |
|----------------------------|-------------------------------------|----------------------------------------------|
| Rear thumb button (Back)   | Move one Space left (active display) | Wispr Flow push-to-talk (held while you hold) |
| Front thumb button (Forward)| Move one Space right (active display)| Wispr Flow push-to-talk (held while you hold) |

The hold action sends **Control + Option + F13**, a chord no MacBook keyboard can produce,
so it cannot collide with anything you type. You teach that chord to Wispr Flow once (step 4).

### Important: the top button cannot be remapped by any software
The A7851 is a 5-button mouse: left, right, wheel-click, Back, and Forward. The small button on
the top ridge (your first red box) is the **DPI switch** (1000/1600). It is handled inside the
mouse's firmware and never sends anything to the Mac, so macOS, ThumbMap, BetterTouchTool,
SteerMouse and every similar tool are blind to it. Step 3 lets you confirm this yourself.
That is why ThumbMap gives you three functions from the two thumb buttons using tap vs. hold.

## Install

1. Install Apple's command-line tools if you have not already: `xcode-select --install`
2. In Terminal, from this folder: `chmod +x install.sh uninstall.sh && ./install.sh`
3. Approve **ThumbMap** under System Settings → Privacy & Security → Accessibility.
   Then run `tail -f ~/Library/Logs/ThumbMap.log` and press each button. You should see
   `button 3 pressed` and `button 4 pressed`. Pressing the top DPI button logs nothing.
4. **Teach Wispr Flow the chord.** Open Wispr Flow → Settings → Keyboard shortcuts, click
   into the *Push to talk* row, then in Terminal run `pkill -USR1 -x ThumbMap`. Within
   4 seconds click back into the Wispr row; ThumbMap will press Ctrl+Option+F13 for 1.5 s and
   Wispr records it. (You can add it alongside Fn; Wispr allows several shortcuts per action.)
5. Make sure the Spaces shortcuts are on: System Settings → Keyboard → Keyboard Shortcuts →
   Mission Control → enable *Move left a space* and *Move right a space* (Control-← / Control-→).

## Notes

- **"Active monitor":** with *Displays have separate Spaces* on (System Settings → Desktop &
  Dock, the default), Control-←/→ moves the Spaces of the display you're working on.
- **Latency:** because each thumb button has a hold action, the Space switch fires on release
  of a quick click. If you remove a button's `hold`, its tap fires instantly on press.
- Mapped buttons are swallowed, so browsers will no longer go Back/Forward with them.

## Customizing `~/.config/thumbmap/config.json`

Button numbers: 2 = wheel click, 3 = Back, 4 = Forward. Each button takes `tap` and/or `hold`.

| `type`           | Extra fields                       | Effect                                       |
|------------------|------------------------------------|----------------------------------------------|
| `spaceLeft` / `spaceRight` | —                        | Control-← / Control-→                        |
| `missionControl` | —                                  | Control-↑                                    |
| `appWindows`     | —                                  | Control-↓ (App Exposé)                       |
| `keys`           | `keyCode`, `modifiers`             | Key chord; held for the duration of a hold    |
| `mouseButton`    | `button`                           | Synthesizes another mouse button (e.g. 6)     |
| `shell`          | `command`                          | Runs a shell command, e.g. `open -a Notes`    |
| `none`           | —                                  | Do nothing (button is still swallowed)       |

Modifiers: `control`, `option`, `command`, `shift`. Common key codes: F13 = 105, F14 = 107,
F15 = 113, Space = 49. Set `holdThresholdMs` to taste (250–400 feels natural).
After editing, run `pkill -HUP -x ThumbMap` to reload; no restart needed.

**Alternative layouts worth considering**
- Bind Wispr's *Hands-free* mode natively to the wheel click (Wispr supports middle click
  directly), and keep the thumb buttons purely for Spaces with no hold, giving instant switching.
- If Wispr does not register the synthetic chord, change the hold to
  `{ "type": "mouseButton", "button": 6 }` and record that as Wispr's push-to-talk instead.

## Troubleshooting

- **Nothing happens:** check the log. "Waiting for Accessibility permission" means step 3.
- **Stopped working after re-running install.sh:** a rebuilt app needs re-approval in Accessibility.
- **Spaces do not switch:** confirm step 5 and that you have more than one Space on that display.
- **Uninstall:** `./uninstall.sh` (add `--purge` to delete config and log).
