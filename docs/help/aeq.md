# Audio Equalizer

Live three-band tone control from an input to an output.

## Wiring

| Signal | myDAQ terminals |
|---|---|
| **Audio in** | AUDIO IN jack, L / R, ±2 V |
| **Audio out** | AUDIO OUT jack, L / R, ±2 V |
| **AI 0 / AI 1**, **AO 0 / AO 1** | Screw terminals, alternative kind |

- Inputs share one converter, outputs another: each side is one kind, picking a kind sets both channels.
- Simulator: outputs loop back to the inputs. Choose **AI 0 / AI 1** in and **Audio out** to hear test signals.

## Header

| Control | Effect |
|---|---|
| **Run** / **Stop** | Start the stream |
| **Bypass** | Skip the equalizer, volume still applies |
| **Flat** | All bands to 0 dB |

## Faders

| Fader | Range |
|---|---|
| **Bass** | ±12 dB, below 320 Hz |
| **Midtone** | ±12 dB, 320 Hz to 2.56 kHz |
| **Treble** | ±12 dB, 2.56 to 20.84 kHz |
| **Volume** | Percent |

Drag, wheel, arrows or type a value; double-click resets. 4th-order Bessel bands, summed.

## Cards

| Card | Controls |
|---|---|
| **Input** | **Type**; **Left** and **Right** source In L, In R, Off |
| **Output** | **Type**; **Left** and **Right** destination Out L, Out R, Off |

One source feeds both outputs.

## Tools

| Tool | Contents |
|---|---|
| **Streaming** | **Sample rate** 50, 100, 200 kS/s; **Output buffer**; dropout count |
| **Display** | **Spectrum** / **Time**; **L** / **R**; **Averaging**; **Time span**; **Autoscale**; **Show input** |

## Display

| Item | Meaning |
|---|---|
| Top plot | Tone response and each band curve |
| **Before** / **After** | Input and output spectrum, dBV |
| Meters | **In** and **Out**, L and R; amber from −12 dB, red from −3 dB |
| Clipped | Output beyond ±2 V |
| Latency | About buffer plus 10 ms |

## Keys

| Key | Effect |
|---|---|
| Space | **Run** / **Stop** |
| ↑ ↓ | Move the focused fader |

## Tips

- Clipping: lower **Volume** or the gains.
- Dropouts restart the stream: lengthen the output buffer.
- Another instrument holding the converters pauses the equalizer; **Resume** afterwards.

See [Getting started](app.md).
