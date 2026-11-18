# Waveform Generator

Two output channels: functions, sweeps, DC and arbitrary waveforms.

## Wiring

| Output | myDAQ terminals |
|---|---|
| **AO 0 / AO 1** | AO 0, AO 1 against AGND, ±10 V, DC-coupled |
| **Audio out** | AUDIO OUT jack, L / R, ±2 V, AC-coupled, up to 4 Vpp |

- Loop to the scope: AO 0 to AI 0+, AGND to AI 0−.
- A few mA only: buffer low-impedance loads.
- Both channels use the same output pair.

## Header

| Control | Effect |
|---|---|
| **Run** / **Stop** | Start all channels; Stop returns outputs to 0 V |
| **Single** | Play every **Arb** channel once |
| **Time** **Frequency** | Volts over time, or spectrum in dBV |
| **AO 0 / AO 1** **Audio out** | Output pair |

## Channel card

| Control | Effect |
|---|---|
| Card switch | Output on or off (0 V) |
| **Sine** **Sq** **Tri** **DC** **Arb** | Waveform; click the picked one again for off |
| **Frequency** | 0.2 Hz to 20 kHz |
| **Amplitude** | 0 to 10 Vpp |
| **Offset** | ±5 V |
| **Duty cycle** | Square only |
| **Phase** | Degrees |
| **Level** | **DC** only, ±10 V |

Knob changes apply live, phase-continuous. DC is not available on audio.

## Arb

| Control | Effect |
|---|---|
| Open…, Library | File (`.mbw` `.wav` `.csv` `.txt` `.bin` `.wdt` `.wfm`) or built-in shape |
| **Open in Editor** | Edit or draw the waveform |
| **Gain** | Multiplier; clipped samples are counted |
| **Update rate** | Samples per second |
| **Continuous** / **Once** | Repeat, or one pass; **Then 0 V** returns to 0 V |
| **Hold** / **Linear** | Between samples |
| **Same rate as AO 0** | Shared rate when both are **Arb** |

## Tools

| Tool | Contents |
|---|---|
| **Sweep** | Per function channel: **Start**, **Stop**, **Step**, **Interval**; **Start Sweep** |
| **Presets** | **Built-in**, **Saved**, **Save Current Settings…** |

Sweep locks frequency; amplitude, offset, duty stay live.

## Options menu

| Entry | Effect |
|---|---|
| **Waveform Editor** | Open the editor |
| **Align Phases** | Restart both function channels at phase 0 |
| **Export AO 0 Waveform…** | CSV or WAV, per channel |

## Waveform Editor

| Part | Contents |
|---|---|
| Bar | Back to the Generator, Undo, Redo, **Zoom to Fit**, New, Open, Save, **Send to Generator** |
| Segment list | Segments in play order; **New Segment**, **New Component**, move up / down |
| **Document** card | Name, points, duration, sample rate, units, **Live update** |
| **Segment** card | Name, duration, gain; components with **Combine** + − × / FM |
| **Draw** | Freehand or line, one cycle |
| **Functions** | Library functions, f(x), Sketch |
| **Scale**, **Display**, **Export**, **Info** | Scale selection; plot options; CSV, WAV, binary; document info |

## Keys

| Key | Effect |
|---|---|
| Space | **Run** / **Stop** |
| Shift+Space | **Single** |
| Ctrl+N / O / S / W | Editor: new, open, save, close |
| Ctrl+Shift+S | Editor: save as |
| Ctrl+Z / Y, Ctrl+Shift+Z | Editor: undo, redo |
| Ctrl+X / C / V / A | Editor: cut, copy, paste, select all |
| Ctrl+0 | Editor: zoom to fit |
| Del | Editor: clear selected segments |

## Tips

- Double-click a knob: default value.
- Command palette: **Set AO 0 to … V**.
- Bode takes the outputs: the generator pauses, **Resume** restarts it.
- Frequency above half the sample rate shows aliasing.

See [Getting started](app.md).
