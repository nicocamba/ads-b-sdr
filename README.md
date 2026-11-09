# ADS-B SDR Receiver in MATLAB

A coursework project that builds a receive-only 1090 MHz ADS-B / Mode S receiver around an Analog Devices ADALM-PLUTO SDR. The MATLAB scripts take complex IQ samples from the radio, find Mode S preambles, demodulate the pulse-position-modulated bits, check the frame CRC, and decode selected ADS-B fields.

This is an experimental receiver and learning project. The decoder currently extracts selected message fields; it does not yet reconstruct aircraft positions from the CPR latitude/longitude fields.

## Processing pipeline

```text
ADALM-PLUTO at 1090 MHz
        |
        v
IQ_Reception.m         Capture IQ samples and acquisition diagnostics
        |
        v
preamble_detection.m   Search power samples for Mode S preambles
        |
        v
ppm_demodulation.m     Recover 112 bits using half-bit energy comparison
        |
        v
crc_validation.m       Keep DF17 frames with a zero 24-bit CRC remainder
        |
        v
adbs_decoding.m        Decode selected ADS-B message fields
```

Each stage reads and writes MATLAB `.mat` files in `data/`. These generated captures and processing outputs are not included in the repository. Run the scripts in the order shown. The acquisition script requires the radio; the later stages process the saved capture offline.

## Project structure

```text
.
├── IQ_Reception.m
├── preamble_detection.m
├── ppm_demodulation.m
├── crc_validation.m
├── adbs_decoding.m
└── data/
    └── README.md
```

The `.mat` files are generated outputs and are not committed to this repository. `IQ_Reception.m` creates the initial capture; the remaining scripts create their own intermediate and final files under `data/`. Live capture requires an ADALM-PLUTO. To run only the offline stages, provide your own `data/adsb_capture.mat` with the variables described in the scripts.

## Requirements

- MATLAB.
- Communications Toolbox and the Communications Toolbox Support Package for Analog Devices ADALM-PLUTO for `sdrrx('Pluto', ...)` acquisition.
- Signal Processing Toolbox for spectrum analysis with `pwelch`.
- An ADALM-PLUTO SDR connected over USB for live capture. The scripts use the Pluto device ID `usb:0`.

MATLAB toolbox availability can vary by release. The acquisition stage also needs the Pluto support package installed and the radio visible to MATLAB.

## Run the receiver

1. Connect the Pluto SDR and run `IQ_Reception.m`. It tunes to 1090 MHz, samples at 5 MS/s, discards one startup frame, captures 50 frames of 500,000 samples (5 seconds), and saves `data/adsb_capture.mat` with frame-validity and overflow diagnostics.
2. Run `preamble_detection.m`. It calculates signal power, searches eight fractional-sample template phases, and saves preamble candidates and their scores to `data/adsb_preamble_detections.mat`.
3. Run `ppm_demodulation.m`. It integrates energy over the two 0.5 μs halves of each 1 μs bit and saves 112-bit candidate frames and confidence/energy information to `data/adsb_demodulated_messages.mat`.
4. Run `crc_validation.m`. It filters for DF17 (ADS-B Extended Squitter), computes the Mode S polynomial remainder across all 112 bits, and saves frames with a zero remainder to `data/adsb_valid_messages.mat`.
5. Run `adbs_decoding.m`. It decodes selected message fields and saves the resulting structs to `data/aircraft_data.mat`.

The scripts use relative paths based on their own location, so they can be launched from MATLAB without first changing the current folder.

## What the decoder extracts

- **Type Codes 1–4:** aircraft identification / callsign.
- **Type Codes 5–8:** surface movement and raw CPR latitude/longitude fields.
- **Type Codes 9–18:** airborne position fields and barometric altitude when the supported encoding is present.
- **Type Code 19:** selected airborne velocity and heading fields.
- **Type Codes 20–22:** airborne position fields and GNSS altitude.

The CPR values are retained as encoded fields; the project does not yet combine even/odd CPR frames into latitude and longitude. Some velocity subtypes and the Q=0 Gillham barometric-altitude encoding are also not implemented.

## Configuration and interpretation

- Center frequency: **1090 MHz**.
- Baseband sample rate: **5 MS/s**.
- Capture duration: **5 seconds** (50 × 100 ms frames, excluding the discarded startup frame).
- ADS-B extended squitter: **112 bits**, following an 8 μs preamble.
- Preamble detector: eight phase offsets and a robust median/MAD-based score threshold.

The capture script stores every frame and plots the full acquisition. The preamble detector also forms large full-length arrays; for the included 25-million-sample capture, these stages can use several hundred megabytes of memory. Reduce the capture length or process samples in chunks if memory is limited.

`validFrames` and `overflowFrames` are recorded during acquisition. The preamble detector currently handles reported overflows by discarding data from the first overflow onward, but it does not filter individual frames marked invalid when no overflow is reported. Treat detection counts as experimental results, not as a calibrated receiver sensitivity or false-alarm measurement.

## Audit notes

- Corrected the Q=1 barometric altitude extraction to use all 11 altitude bits after removing only the Q bit. The original code omitted one additional bit, producing incorrect altitudes.
- Clarified the CRC comment: DF17 uses direct parity (no ICAO address overlay), so a valid complete frame produces a zero remainder. The CRC comparison itself already used this criterion.
- The Q=0 Gillham altitude path is not implemented and returns `NaN`.
- The code has not been run in MATLAB as part of this static audit; hardware and toolbox dependencies prevent claiming a verified live capture.

## References

- Junzi Sun, [The 1090 MHz Riddle: Mode S parity](https://mode-s.org/1090mhz/content/mode-s/1-basics.html).
- Junzi Sun, [The 1090 MHz Riddle: Mode S altitude code](https://mode-s.org/1090mhz/content/mode-s/3-surveillance.html).
- [GitHub: About Git Large File Storage](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-git-large-file-storage).



