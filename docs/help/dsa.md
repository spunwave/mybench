# Spectrum Analyzer

FFT spectrum, distortion figures and 1/3-octave bands of one input.

## Wiring

| Signal | myDAQ terminals |
|---|---|
| **AI 0**, **AI 1** | AI x+ / AI x−, AGND reference, ±10 V or ±2 V |
| **Audio L**, **Audio R** | AUDIO IN jack, ±2 V fixed |

- Shares the analog inputs with Scope, Bode and Logger: the one started first pauses.

## Header

| Control | Effect |
|---|---|
| **Run** / **Stop** | Acquire continuously |
| **Single** | Complete the averaging, then stop |
| Span knob | 0 Hz to span, 1-2-5 steps, 100 kHz max on AI; rate is 2× |
| Lines knob | 200 to 3200; df = span / lines |
| **Spectrum** / **Octave** | FFT analyzer, or 1/3-octave bands |
| Avg n/N | Averaging progress |

## Input card

| Control | Effect |
|---|---|
| **AI 0** **AI 1** **Audio L** **Audio R** | Source |
| **Range** | **±10 V** or **±2 V**, AI only |

## Tools

| Tool | Contents |
|---|---|
| **Window** | Shape before the FFT: None, Hanning, Flat Top, Blackman-Harris |
| **Averaging** | **Mode** None, Vector, RMS, Peak Hold; **Weighting** Linear, Exponential; **Averages**; **Reset Averaging** |
| **Display** | **Units** V, dB, dBm; RMS or Peak; **Power** / **Density**; **Vertical scale**; log frequency; **Max hold**, **Min hold**; **Time record**; **Spectrogram** |
| **Cursors** | **Harmonic markers**; **Peaks table**; C1, C2; **Selected cursor**; **Peak search** |
| **Export** | Data, image, PDF; ELVISmx text log |

Window: None suits exact-fit signals, Flat Top gives exact peak amplitudes.

## Measurements

| Name | Meaning |
|---|---|
| **Fundamental** | Strongest peak, refined between lines |
| **Fundamental power** | Peak power over ±3 lines, always linear (Vrms²) |
| **THD** | Harmonics 2 to 10 against the fundamental |
| **SINAD** | Signal over noise and distortion |
| **SNR** | Like SINAD, harmonics not counted as noise |
| **Peak** | Half of highest minus lowest sample |
| C1, C2, Δ | Cursor positions and differences |

Cards show min, max, mean, σ over the last 100 results.

## Octave

| Control | Effect |
|---|---|
| **Mode** | Time weighting: **Slow** 1 s, **Fast** 125 ms, **Impulse**, **Custom** |
| **Weighting** | Linear, or A, B, C |
| **Bands** | 31 bands, 20 Hz to 20 kHz; Low and High limits |
| **Settled** | Low-band filters are valid |
| **Overall level**, **Loudest band** | Cards |

Source sampled at 50 kS/s.

## Graph

| Action | Effect |
|---|---|
| Hover | Value under the pointer |
| Wheel, drag | Zoom, pan |
| Double-click | Restore view |
| **F**, H2 to H10 | Fundamental and harmonic markers, level in dBc |

## Keys

| Key | Effect |
|---|---|
| Space | **Run** / **Stop** |
| Shift+Space | **Single** |

## Tips

- Wide peaks with skirts: choose a window.
- Frozen spectrum: Linear weighting finished; **Reset Averaging** or use Exponential.
- Peaks at wrong frequencies: aliasing, raise the span.
- Lost samples restart the averaging; three within 10 s stop the run.

See [Getting started](app.md).
