# Oscilloscope

Two voltages over time, with trigger, cursors, math and FFT.

## Wiring

| Signal | myDAQ terminals |
|---|---|
| **AI 0** | AI 0+ / AI 0−, ±10 V or ±2 V, up to 200 kS/s |
| **AI 1** | AI 1+ / AI 1−, same |
| Reference | AGND |
| **Audio L / Audio R** | AUDIO IN jack, tip / ring, ±2 V |

- AI is differential: it shows AI x+ minus AI x−. Tie AI x− to AGND for a ground-referenced signal.
- Audio is AC-coupled. AI and audio share the converters: both channels use the same kind.

## Header

| Control | Effect |
|---|---|
| **Run** / **Stop** | Acquire continuously |
| **Single** | One screen, then stop |
| Timebase knob | 5 µs to 200 ms per division |
| Position knob | Trigger point on screen, 0 to 100 % |
| **YT** **XY** **FFT** | Time view, CH1 over CH0, spectrum below |
| **Autoscale** | Scale and timebase to fit, about 5 periods |

## Cards

| Card | Controls |
|---|---|
| **CH 0**, **CH 1** | Switch; **Scale** 10 mV to 5 V/div; **Position** ±5 div; **Source** AI / Audio; **Range** Auto, ±10 V, ±2 V |
| **Trigger** | **Immediate** / **Edge**; **Auto** / **Normal**; **Source** CH0 / CH1; **Slope**; **Level** |
| Trigger, more | **Timeout**, **Holdoff**, **Hysteresis**, **Clear while waiting** |
| **Math** | Switch; CH0+CH1, CH0−CH1, CH0×CH1, −CH0, −CH1; **Scale**; **Position** |

## Tools

| Tool | Contents |
|---|---|
| **Measure** | Measurement buttons; **Trace** All / CH0 / CH1 / Math; **Statistics** Off / Last 100 / All; **Frequency** Tone / Edges |
| **Cursors** | **Time Cursors** C1, C2 with trace and **Style**; **Level Cursors** H1, H2 |
| **Refs** | Keep CH0, CH1 or Math as REF A / REF B; show, import, export, clear |
| **Display** | **Persistence**, **Averaging**, **Record** Normal / Long, **Roll** from 50 ms/div, **Auto level**, **Trace Styles…** |

## Measurements

| Name | Meaning |
|---|---|
| RMS, AC RMS | Whole screen, with / without DC |
| Frequency | **Tone**: spectral peak. **Edges**: mid-level crossings |
| Pk-pk, Peak | Max − min; max \|v\| |
| Mean, Min, Max, Amplitude | Level statistics |
| Period, Duty, + Width, − Width | Timing |
| Rise, Fall | 10 to 90 % |
| Crest, Overshoot, Preshoot, Slew | Shape |
| Phase | CH1 against CH0, periodic signals |
| Δt, 1/Δt, ΔV | Cursor differences, first cards |

## Graph

| Action | Effect |
|---|---|
| Drag **0** / **1** / **M** | Trace position |
| Drag **T** (right) / (top) | Trigger level / position |
| Wheel | Timebase |
| Shift + wheel | Scale of nearest trace |
| Hover | Values of every trace |
| Double-click | Fit view |

## Keys

| Key | Effect |
|---|---|
| Space | **Run** / **Stop** |
| Shift+Space | **Single** |
| ← → | Move the selected cursor one sample |
| Esc | Close the open tool |

## Tips

- Edge trigger with **Level** inside the signal steadies the trace.
- AO 0 to AI 0+, AGND to AI 0−: view the Generator.
- Frequency shows `?`: signal under 0.2 div, or under one period on screen.
- **Roll** is untriggered and needs 50 ms/div or slower.
- The scope pauses while Bode, Spectrum or Logger take the inputs; **Resume** takes it back.

See [Getting started](app.md).
