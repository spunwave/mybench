# mybench

NI myDAQ instruments in one window; a simulated myDAQ runs without hardware.

## Instruments

| Instrument | myDAQ terminals |
|---|---|
| [Multimeter](dmm.md) | Banana jacks HI, COM, HI (A) |
| [Oscilloscope](scope.md) | AI 0, AI 1, AUDIO IN |
| [Bode Analyzer](bode.md) | AO 0, AI 0, AI 1 |
| [Spectrum Analyzer](dsa.md) | AI 0, AI 1, AUDIO IN |
| [Waveform Generator](gen.md) | AO 0, AO 1, AUDIO OUT |
| [Digital I/O](dio.md) | DIO 0 to 7, DGND |
| [Counter/Timer](ctr.md) | DIO 0 to 4 |
| [Data Logger](log.md) | AI 0, AI 1, DMM |
| [Audio Equalizer](aeq.md) | AUDIO IN, AUDIO OUT |

## Window

| Part | Contents |
|---|---|
| **Sidebar** | **Overview** and the instruments, in **Measure**, **Generate**, **Digital**, **Apps** |
| Sidebar row | Click to show; Space runs or stops; context menu **Show Beside**, **Run**, **Single**, **Reset Settings…** |
| Toolbar | Sidebar toggle, session name, **Stop All**, device menu, **Search** |
| Workspace | One pane, or two side by side (**Show Beside**, Ctrl+\\) |
| Inspector | Right dock: **Settings** / **Help** for the focused pane (Ctrl+I) |
| Status bar | Device state, resources in use, **Event Log** |

- A myDAQ that is plugged in but cannot be opened shows **Not available** with the cause; no myDAQ: **Use Demo**. See [Device](device.md).
- Showing an instrument never stops another.
- Sidebar dot: green running, amber paused, red error.
- Drag a sidebar row or tile onto a pane edge to split, onto the middle to replace.
- A narrow window compacts the sidebar; a narrow split pane wraps its header.
- A split pane has an × (**Close Split**); it never stops the instrument.

## Pane header

| Icon | Effect |
|---|---|
| Run, Single | Start; one pass |
| Show / Hide Inspector | Dock on the right (Ctrl+I) |
| Export | **Export Data…** (Ctrl+E), **Export Image…**, **Print…** |
| Reset | Settings to defaults, after confirming |
| Help | This drawer (F1) |
| Instrument Options | Instrument commands, **Trace Style…**, **Show Measurements** |

**Release Outputs** appears while a stopped instrument still drives outputs.

## Overview

| Part | Contents |
|---|---|
| Device | State, **Info…**, **Simulator…**, **Use Simulator**, **Reset…** |
| **Instruments** | Live tiles; click to show; **Run** / **Stop** on hover; **Show Beside**, **Pin to Top** |
| **Recent Sessions** | Last saved `.mybench` files |
| **Reset All…** | Stop everything, restore settings, keep the layout |

## Sharing the myDAQ

| Resource | Users |
|---|---|
| Analog inputs | One of Scope, Spectrum, Bode, Logger, Equalizer (audio in too) |
| Analog outputs | Generator or Bode |
| DMM, Digital I/O | Independent; Digital I/O shares lines with Counter |

The loser pauses with a banner; **Resume** takes it back.

## Graphs

| Action | Effect |
|---|---|
| Hover toolbar | Pointer, zoom menu, pan, autoscale X / Y with lock |
| Wheel | Zoom time or frequency |
| Shift + wheel | Zoom vertically |
| Ctrl + drag | Zoom box |
| Drag | Pan |
| Double-click | Fit |
| Right-click | Autoscale, undo zoom, cursors, **Trace Style…**, copy, export |

## Sessions

| Command | Effect |
|---|---|
| New, Open…, Save, Save As… | `.mybench` files; instruments are not started on open |
| Revert to Saved | Back to the last save |
| Preferences (Ctrl+,) | **General**, **Appearance**, **Instruments**, **Device**, **Tools** |

Layout and settings are restored at the next start. **Edited** marks unsaved changes.

## Keys

Ctrl is ⌘ on macOS.

| Key | Effect |
|---|---|
| Space, Shift+Space | Run / Stop, Single |
| Ctrl+R, Ctrl+Shift+R | Run / Stop, Single |
| Ctrl+. | **Stop All** |
| Ctrl+K | Command palette |
| F1 | Help |
| Ctrl+0 | **Overview** |
| Ctrl+1 to 9 | Show instrument, in sidebar order |
| Ctrl+Tab | Next instrument |
| Ctrl+\\ | **Show Beside** / **Close Split** |
| Ctrl+Alt+S | Sidebar |
| Ctrl+I | Inspector |
| Ctrl+E, Ctrl+Shift+E, Ctrl+P | Export data, export image, print |
| Ctrl+N, Ctrl+O, Ctrl+S, Ctrl+Shift+S | Session new, open, save, save as |
| Ctrl+, | Preferences |
| F11 | Full screen |
| Esc | Close the open tool or overlay |

## Tips

- Space belongs to a focused button, field or list.
- Numbers take units: `1k`, `2.5m`, `100 mV`. Arrow keys step a focused knob.
- Command palette lists instrument commands; type a value, then Return.
- Simulator: AO 0 wired to AI 0 directly, and to AI 1 through a low-pass.
- Errors: banner with **Details**, full text in **Event Log**.
- No device: check the USB cable, then **Rescan** in the device menu.
