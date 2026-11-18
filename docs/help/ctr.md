# Counter/Timer

Frequency, period, pulse width, edge count, encoders and pulse output.

## Wiring

| Terminal | Counter signal | Used by |
|---|---|---|
| DIO 0 | CTR 0 SOURCE | **Count** edges; encoder A, two-pulse up |
| DIO 1 | CTR 0 GATE | **Frequency**, **Period**, **Width**, **Semi** input; **Two-Edge** second edge; reset; **Z index** |
| DIO 2 | CTR 0 AUX | **Two-Edge** first edge; count direction; encoder B, two-pulse down |
| DIO 3 | CTR 0 OUT | **Pulse Train** output |
| DIO 4 | FREQOUT | Square-wave output |

- 3.3 V logic, 5 V tolerant inputs, reference DGND.
- A line held by Digital I/O is marked in **Pins**; Run pauses Digital I/O.

## Header

| Control | Effect |
|---|---|
| **Run** / **Stop** | Measure or generate; reads **No input** until a reading arrives |
| **Single** | One reading, or stop after the next |
| Reset Stats (beside the cards) | Clear statistics |

## Mode

| Button | Measures |
|---|---|
| **Frequency**, **Period** | Between two active edges of DIO 1 |
| **Width** | High time (rising) or low time (falling) |
| **Semi** | Time between any two edges |
| **Two-Edge** | DIO 2 edge to DIO 1 edge |
| **Count** | Edges: up, down, or external (DIO 2) |
| **Linear**, **Angular** | Encoder: distance, or degrees and rpm |
| **Pulse Train** | Output on DIO 3 |
| **FREQOUT** | Square wave on DIO 4 only |

## Input card

| Control | Effect |
|---|---|
| **Edge** | Rising or falling |
| **Min freq.** | 1 Hz, 10 mHz, 100 µHz: slowest expected signal, picks the timebase |
| **Acquire** | **On Demand** (latest reading per **Update**) or **Buffered** (every period) |
| Count | **Initial count**; reset on DIO 1 rising edge |
| Encoder | **Decoding** X1, X2, X4 or 2-P; **Z index**; distance per pulse or pulses per rev |

Buffered is not available on the myDAQ; counts and encoders are always on demand.

## Pulse Train

| Control | Effect |
|---|---|
| Frequency and duty, or high and low time | Output timing: 100 MHz divided by an integer |
| **Idle state** | Level before, between and after runs |
| **Initial delay** | Wait before the first pulse |
| **Continuous** / **Finite** | Run until stopped, or a pulse count |

Frequency and duty change while running.

## FREQOUT

| Control | Effect |
|---|---|
| Card switch | Output on DIO 4 |
| Frequency | 6.25 kHz to 20 MHz in fixed steps |

## Readings

| Card | Meaning |
|---|---|
| Measurement | Value with min, max, mean, σ |
| **Readings** | Values in the statistics (**Intervals** when buffered) |

Tools: **Pins** (pin map of the settings), **Export** (trend, image, PDF).

## Keys

| Key | Effect |
|---|---|
| Space | **Run** / **Stop** |
| Shift+Space | **Single** |

## Tips

- Self-test: FREQOUT on, wire DIO 4 to DIO 1, measure **Frequency**.
- Double-click a knob: default.
- Unsupported settings are hidden; a saved one that needs them blocks Run with a warning.
- The myDAQ counts up only; counting down from a non-zero count with reset is refused.

See [Getting started](app.md).
