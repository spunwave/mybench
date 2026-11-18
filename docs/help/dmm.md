# Multimeter

Isolated meter for voltage, current, resistance, diode and continuity.

## Wiring

| Function | Red lead | Black lead |
|---|---|---|
| DC V, AC V, **Ω**, **Diode**, **Continuity** | HI (V Ω) | COM |
| DC A, AC A | HI (A), in series | COM |

- Low-voltage circuits only: 60 V DC, 20 V AC RMS. The current input is fused (1 A).
- Resistance, diode, continuity: circuit off. **Wiring** tool shows the jacks to use.
- Independent of AI and AO: runs beside any instrument.

## Header

| Control | Effect |
|---|---|
| **Run** / **Stop** | Measure continuously |
| **Single** | One reading |
| **Hold** | Freeze the readout, measuring continues |
| **Relative** | Subtract the next reading as null |

## Function

| Button | Ranges |
|---|---|
| **DC V** | 200mV, 2V, 20V, 60V |
| **AC V** | 200mV, 2V, 20V (RMS) |
| **DC A**, **AC A** | 20mA, 200mA, 1A |
| **Ω** | 200Ω to 20MΩ, six decades |
| **Diode** | 2V, drives 1 mA |
| **Continuity** | Auto only; tone below 15 Ω |

**Range**: **Auto** or a fixed range. A real myDAQ pauses about 2.5 s on each range change.

## Readout

| Item | Meaning |
|---|---|
| Value | 3½ digits |
| `+Over` | Input beyond the range |
| `OPEN` | Diode open or reversed |
| Open, Conducts | Continuity 15 Ω or more; diode state |
| Range | Range **Auto** picked |
| Δ from | Null value while **Relative** is on |
| Min, Max, Mean, σ, Count | Since function change or **Reset Statistics** |

## Tools

| Tool | Contents |
|---|---|
| **Logging** | **Record**; **Write to file** (tab, or CSV by name); **Save Log…**; **Clear** |
| **Wiring** | Jack diagram for the function |
| **Options** | **Measure when shown**; **Continuity tone** |

## Keys

| Key | Effect |
|---|---|
| 1 to 7 | Select function, in order |
| Space | **Run** / **Stop** |
| Shift+Space | **Single** |

## Tips

- **Relative** with shorted leads removes lead resistance.
- Small value on a big range: pick a smaller range.
- Overload gives gaps in the trend.
- Current reads 0: red lead in HI (A); check the fuse.

See [Getting started](app.md).
