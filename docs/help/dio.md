# Digital I/O

Read and drive DIO 0 to 7, with a timeline of every line.

## Wiring

| Signal | myDAQ terminals |
|---|---|
| Lines | DIO 0 to DIO 7 |
| Reference | DGND |

- Outputs: 3.3 V logic, a few mA. LEDs need 330 Ω to 1 kΩ.
- Inputs: 0 to 5 V. A floating input reads either level.
- DIO 0 to 4 are shared with Counter and FREQOUT: such a line shows that instrument's name.

## Header

| Control | Effect |
|---|---|
| **Run** / **Stop** | Read and drive until stopped |
| **Single** | One read, write or pattern pass |
| **Hex** **Bin** **Dec** | Radix of values and cursors |
| **Release Outputs** | Outputs back to inputs, shown after a stop |

Green is input, orange is output.

## Line tiles

| Item | Effect |
|---|---|
| **High** / **Low** | State; click an output to flip it (Manual) |
| In / Out buttons | Direction; click the active one to free the line |
| Label | Name from **Labels** |

## Cards

| Card | Controls |
|---|---|
| **Lines** | **Read** and **Write** groups 0–3, 4–7, 0–7, None; **Interval** 10 ms to 1 s |
| **Writer** | Pattern; **Number**; **Toggle**, **Rotate**, **Shift**; **Direction** Left / Right |

## Patterns

| Pattern | Output |
|---|---|
| **Manual** | Tiles or **Number** |
| **Ramp** | Counts up and repeats |
| **Alternate** | 0101 and 1010 |
| **Walking 1** | One high line moving in **Direction** |

**Toggle** inverts; **Rotate** wraps the leaving bit; **Shift** fills with 0.

## Timeline

| Control | Effect |
|---|---|
| **5 s** **10 s** **30 s** **60 s** | Window; last 10 min kept |
| Toolbar | Pointer, zoom, pan, autoscale, cursors, pause, clear |
| Cursors | Time, Δt, state of all lines |

## Tools

| Tool | Contents |
|---|---|
| **Labels** | Name each line |

Export Data (header icon, Ctrl+E): timeline as CSV.

## Keys

| Key | Effect |
|---|---|
| 0 to 7 | Flip that output (Manual) |
| Space | **Run** / **Stop** |
| Shift+Space | **Single** |

## Tips

- Wire DIO 0–3 to DIO 4–7, Writer on 0–3 with **Ramp**, Reader on 4–7.
- Software timed: pulses under the interval are missed.
- Floating inputs: tie to DGND through a resistor.
- A shared line pauses the other instrument; set it free to keep both.

See [Getting started](app.md).
