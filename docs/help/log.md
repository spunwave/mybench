# Data Logger

Slow signals to a live chart and a file: AI 0, AI 1 and the multimeter.

## Wiring

| Channel | myDAQ terminals |
|---|---|
| **AI 0**, **AI 1** | AI x+ / AI x−, differential, same rate |
| **DMM** | Banana jacks as in Multimeter |

- Shares the analog inputs with Scope, Spectrum and Bode.
- The meter delivers 2 readings per second whatever the rate.

## Header

| Control | Effect |
|---|---|
| **Run** / **Stop** | Watch the signals, nothing saved |
| Rate knob | 1 to 1000 S/s per channel |
| **Record** / **Stop Rec** | Write the file; also starts an idle logger |

Channels, rate and limits lock while running.

## Channel cards

| Card | Controls |
|---|---|
| **AI 0**, **AI 1** | Switch; range in use shown (±2 V or ±10 V) |
| **DMM** | Switch; function **DC V** **AC V** **DC A** **AC A** **Ohms**; **Range** |
| **Recording** | File name, size, time; **Pause** / **Resume** writing, the chart keeps running |

## Tools

| Tool | Contents |
|---|---|
| **Log File** | **Folder**, **File name**, **Date in file name**, **Format**, **Timestamps**, **Append to file**, **Record on Run**, **Stop after**, **Show Folder** |
| **Limits** | **Minimum input (V)**, **Maximum input (V)**; within ±2 V uses the ±2 V range |
| **Display** | **Follow** the newest data; overview strip |

## Formats

| Format | Layout |
|---|---|
| **Tab** | `.tsv`, `#` header lines, time in seconds |
| **Comma** | `.csv`, same layout |
| **ELVISmx** | `.txt`, AI only, absolute time, exponent notation |

Existing files are never overwritten: `_2`, `_3` are added.

## Chart

| Action | Effect |
|---|---|
| Toolbar span | 10 s to 1 h, All |
| Wheel, drag | Zoom, pan; stops **Follow** |
| **Clear** | Chart and statistics, not the file |
| Cards | Latest value, min, max, mean, σ |

## Keys

| Key | Effect |
|---|---|
| Space | **Run** / **Stop** |

## Tips

- Limits narrower than ±2 V give finer resolution.
- The file is flushed continuously: a crash keeps everything.
- Export Data (Ctrl+E) saves what the chart holds.

See [Getting started](app.md).
