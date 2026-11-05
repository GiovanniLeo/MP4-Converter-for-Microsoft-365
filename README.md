# MP4 Converter for Microsoft 365

## ⚠️ BEFORE RECORDING: INFORM EVERYONE AND GET EVERYONE'S CONSENT

> [!CAUTION]
> **BEFORE YOU START RECORDING, clearly inform every participant that they will be recorded and obtain each person's explicit agreement. If anyone does not agree, DO NOT RECORD.**
>
> Explain the purpose of the recording and whether it will be transcribed, uploaded to Microsoft 365, or shared with others. Make sure everyone agrees to those uses before proceeding. Inform any participant who joins later and obtain their agreement before including them in the recording.
>
> **Use this tool only with recordings you are authorized to process.** Respect participants' privacy, applicable laws, and your organization's policies. This project cannot obtain or verify consent on your behalf.

A Bash script that converts media into an MP4 with H.264 video and AAC-LC audio, intended for Microsoft 365 upload workflows. It can preserve the source video or add a lightweight black video stream to an audio-only recording.

Conversion runs locally. The script does not upload files or generate transcripts. Transcription availability depends on the Microsoft 365 service, account, and settings.

## Requirements

- Bash 3.2 or later.
- `ffmpeg` with the `libx264` and `aac` encoders, and `ffprobe`, available in `PATH`.
- Standard Unix utilities, including `awk` with `fflush`, `mktemp`, and `mv`.
- An input file with at least one audio stream.

The script has been checked on macOS. Other Unix environments should be verified before use.

## Quick start

Download `convert-mp4-m365.sh`, open a terminal in its directory, and run:

```bash
bash convert-mp4-m365.sh "recording.mp4" "recording-ready.mp4"
```

To run it directly:

```bash
chmod +x convert-mp4-m365.sh
./convert-mp4-m365.sh "recording.mp4" "recording-ready.mp4"
```

## Usage

```text
bash convert-mp4-m365.sh [--black-screen] [--] INPUT [OUTPUT.mp4]
```

Quote paths containing spaces. Relative output paths are resolved from the current working directory. The output directory must already exist, and the output filename must end in `.mp4`.

### Preserve the video

```bash
./convert-mp4-m365.sh "recording.mp4"
```

Creates `recording.m365.mp4` beside the input. Keeps the first video stream excluding cover art and thumbnails, plus the first audio stream. The input must contain both.

### Add a black screen

```bash
./convert-mp4-m365.sh --black-screen "audio.m4a" "recording-ready.mp4"
```

Useful for audio-only recordings, including files named `.mp4` that contain no video. Any original images are replaced with black video. If the output path is omitted, `audio.m365-black.mp4` is created beside the input.

This mode requires a positive duration reported for the first audio stream. It stops with an error if that duration is unavailable.

### Help

```bash
./convert-mp4-m365.sh --help
```

Use `--` before an input filename that starts with a dash:

```bash
./convert-mp4-m365.sh -- "-recording.mp4" "ready.mp4"
```

## Output settings

| Setting | Preserve video | Black screen |
| --- | --- | --- |
| Video | H.264, 8-bit `yuv420p` | H.264, 8-bit `yuv420p` |
| Resolution | Source size, padded to even dimensions | 320 × 240 |
| Frame rate | Based on the source | 1 fps |
| Video encoding | `libx264`, medium preset, CRF 20 | `libx264`, medium preset, CRF 20 |
| Audio | AAC-LC, 128 kbit/s | AAC-LC, mono, 48 kHz, 70 kbit/s |

Both modes use `+faststart` to place the MP4 index at the beginning. Subtitles, data streams, chapters, and source metadata are not copied. Audio and video are re-encoded, so quality and file size can change.

## Progress

When standard error is connected to a terminal, the script displays:

```text
Converting [###############---------------]  50%
```

FFmpeg reports the processed media timestamp through `-progress pipe:1`. The percentage compares that timestamp with the input container duration in default mode, or the first audio stream duration in black-screen mode. It measures processed content, not remaining wall-clock time, and is approximate when stream durations differ.

The percentage stays at or below 99% until conversion finishes and the output is moved into place. If the container duration is unknown in default mode, the display shows processed seconds instead. The bar is hidden when standard error is redirected or captured.

## File handling

- Existing output files are never overwritten.
- Conversion uses a temporary directory inside the output directory.
- The final filename is created only after FFmpeg succeeds.
- Temporary files are cleaned up on normal exit, conversion failure, Ctrl+C, or termination with SIGTERM. Forced termination such as SIGKILL can leave temporary files behind.
- The source file is left unchanged.

## Troubleshooting

| Message | Action |
| --- | --- |
| `FFmpeg is not available in PATH.` | Install FFmpeg and ensure `ffmpeg` is available in the terminal. |
| `ffprobe is not available in PATH.` | Ensure the FFmpeg installation also provides `ffprobe`. |
| `The input does not contain an actual video stream.` | Use `--black-screen` for audio-only input. |
| `The input does not contain an audio stream.` | Choose an input containing audio; both modes require it. |
| `Cannot determine the duration of the first audio stream.` | Black-screen mode requires valid audio stream duration metadata. |
| `Output already exists:` | Choose a different output path. |
| `Conversion failed.` | Read the FFmpeg error printed above it; check file integrity and encoder availability. |
