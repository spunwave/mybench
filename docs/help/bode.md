# Bode Analyzer

Gain and phase of a circuit against frequency.

## Wiring

| Signal | **AI 0/1** (default) | **Audio L/R** |
|---|---|---|
| Stimulus out | **AO 0** or **AO 1** to the circuit input | **Audio** out (L and R carry the same sine) |
| Stimulus in | Same node to AI 0+ | Same node to Audio In L |
| Response | Circuit output to AI 1+ | Circuit output to Audio In R |
| Grounds | AI 0−, AI 1−, circuit ground to AGND | Audio ground |

| Path | Limits |
|---|---|
| AO 0, AO 1, AI 0/1 | ±10 V outputs, 0 to 5 V amplitude, from 1 Hz |
| Audio out or Audio L/R | ±2 V, AC coupled: from 20 Hz, amplitude at most 1.8 V (a lower Start or higher Amplitude is limited for the run, with a notice) |

- Any output works with any input pair. In the simulator only AO 0 → AI 0/1 and Audio → Audio L/R are wired: other combinations end with "No stimulus signal".
- Uses the chosen output and both inputs: Generator, Scope and Spectrum pause while it runs.
- **Wiring** tool shows the diagram.

## Header

| Control | Effect |
|---|---|
| **Sweep** / **Stop** | One run from **Start** to **Stop**, with progress |
| **Start**, **Stop** knobs | 1 Hz to 20 kHz, log; Start above Stop is refused |
| Amplitude knob | Stimulus peak, 0 to 5 V |
| **Keep as Reference** | Store the sweep, shown dashed |

## Sweep card

| Control | Effect |
|---|---|
| **Stimulus** | **AO 0**, **AO 1** or **Audio** output |
| **Inputs** | **AI 0/1** or **Audio L/R** (stimulus on the first, response on the second) |
| **Steps** | Points per decade, 1 to 1000 |
| **Standard** / **Fast** | Range pre-measurement per point, or none |
| **Normal** / **Invert** | Invert reads an inverting amplifier as 0° |
| **Averages** | 1 to 16 records per frequency |

Locked while sweeping (not **Normal** / **Invert**, which applies afterwards too).

## Tools

| Tool | Contents |
|---|---|
| **Graph** | Gain **dB** / **Ratio**; frequency **Log** / **Linear**; **Autoscale**; **Unwrap phase** |
| **Cursors** | C1, C2 on both plots; step buttons; **Remeasure C1**; **Markers** |
| **Refs** | Up to 8 references: rename, show, export, delete |
| **Wiring** | Connection diagram |

**Markers**: **−3 dB**, **0 dB crossover**, **Gain / phase margin**.

## Result cards

| Card | Meaning |
|---|---|
| **Last point** | Newest frequency, gain, phase; cursors C1, C2, Δ and slope when on |
| **f−3dB** | Gain 3 dB below maximum |
| **0 dB at f** | Unity-gain frequency |
| **Gain margin**, **GM at f** | Margin where phase crosses −180° |
| **Phase margin** | 180° plus phase at 0 dB |
| **Max gain** | Peak of the gain trace |

## Keys

| Key | Effect |
|---|---|
| Space | **Sweep** / **Stop** |

## Tips

- Clipped point: lower the amplitude.
- Gain 0 dB, phase 0° everywhere: the response input sits on the stimulus.
- Noisy at high attenuation: raise amplitude or **Averages**.
- **Fast** suits mid and high frequencies.
- The analog output returns to 0 V after the sweep.

See [Getting started](app.md).
