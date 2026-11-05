#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage
  bash convert-mp4-m365.sh [--black-screen] [--] INPUT [OUTPUT.mp4]

  Default mode          Keeps the first actual video and first audio stream.
                        Encodes as 8-bit H.264 and AAC-LC.
  --black-screen        Replaces video with black at 320x240 and 1 fps.
                        Encodes the first audio stream as mono AAC-LC, 48 kHz.

Requires FFmpeg with the libx264 and aac encoders, plus ffprobe.
Both modes require an audio stream. For audio-only input, use --black-screen
to add a black video stream.
The output is an MP4 with its index at the beginning (+faststart).
Shows a conversion progress bar when stderr is connected to a terminal.
Excludes subtitles, data streams and chapters. Never overwrites existing files.
Transcript generation depends on the Microsoft 365 service.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

show_progress() {
  LC_ALL=C awk -v duration="$duration" -v visible="$progress_visible" '
    BEGIN { FS = "=" }
    $1 == "out_time_us" && $2 ~ /^[0-9]+$/ && visible {
      seconds = $2 / 1000000
      if (duration > 0) {
        percent = int(seconds * 100 / duration)
        # Show 100% only after the output file has been published.
        if (percent > 99) percent = 99
        bar = ""
        for (i = 0; i < 30; i++) bar = bar (i < int(percent * 30 / 100) ? "#" : "-")
        printf "\rConverting [%s] %3d%%", bar, percent > "/dev/stderr"
      } else {
        printf "\rConverting: %d s processed", seconds > "/dev/stderr"
      }
      fflush("/dev/stderr")
    }
  '
}

mode=video
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --black-screen) mode=black; shift ;;
esac
if [[ "${1:-}" == -- ]]; then
  shift
fi
if (( $# < 1 || $# > 2 )); then
  usage >&2
  exit 2
fi

command -v ffmpeg >/dev/null 2>&1 || fail "FFmpeg is not available in PATH."
input=$1
[[ -f "$input" && -r "$input" ]] || fail "Input file is not readable: $input"
[[ "$input" == /* ]] || input="$PWD/$input"

command -v ffprobe >/dev/null 2>&1 || fail "ffprobe is not available in PATH."
audio_stream=$(ffprobe -v error -select_streams a:0 -show_entries stream=index \
  -of default=noprint_wrappers=1:nokey=1 -i "$input")
[[ -n "$audio_stream" ]] || fail "The input does not contain an audio stream."
if [[ "$mode" == video ]]; then
  video_stream=$(ffprobe -v error -select_streams V:0 -show_entries stream=index \
    -of default=noprint_wrappers=1:nokey=1 -i "$input")
  [[ -n "$video_stream" ]] ||
    fail "The input does not contain an actual video stream. Use --black-screen to convert an audio-only file."
fi

if [[ "$mode" == black ]]; then
  output=${2:-"${input%.*}.m365-black.mp4"}
  seconds=$(ffprobe -v error -select_streams a:0 -show_entries stream=duration \
    -of default=noprint_wrappers=1:nokey=1 -i "$input")
  [[ "$seconds" =~ ^[0-9]+([.][0-9]+)?$ && ! "$seconds" =~ ^0+([.]0+)?$ ]] ||
    fail "Cannot determine the duration of the first audio stream."
  video_source=(-f lavfi -i "color=c=black:s=320x240:r=1:d=$seconds" -map 1:v:0)
  audio=(-af 'asetpts=PTS-STARTPTS' -ac 1 -ar 48000 -b:a 70k)
else
  output=${2:-"${input%.*}.m365.mp4"}
  seconds=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 -i "$input")
  video_source=(-map 0:V:0 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2')
  audio=(-b:a 128k)
fi

duration=0
if [[ "$seconds" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  duration=$seconds
fi
progress_visible=0
[[ ! -t 2 ]] || progress_visible=1

case "$output" in
  *.[mM][pP]4) ;;
  *) fail "Use the .mp4 extension for the output file." ;;
esac
[[ "$output" == /* ]] || output="$PWD/$output"
[[ ! -e "$output" && ! -L "$output" ]] || fail "Output already exists: $output"
output_dir=${output%/*}
[[ -d "${output_dir:-/}" ]] || fail "Output directory does not exist: $output_dir"

# Publish the result only after FFmpeg has completed the conversion.
temp_dir=$(mktemp -d "$output_dir/.m365-mp4.XXXXXXXX")
trap 'rm -f "$temp_dir/video.mp4"; rmdir "$temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if (( progress_visible )); then
  printf 'Conversion in progress...\n' >&2
fi
if ffmpeg -hide_banner -nostdin -nostats -progress pipe:1 -v error -xerror -n -i "$input" \
  "${video_source[@]}" -map 0:a:0 -map_metadata -1 -map_chapters -1 \
  -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
  -c:a aac -profile:a aac_low "${audio[@]}" \
  -movflags +faststart -f mp4 "$temp_dir/video.mp4" | show_progress; then
  if (( progress_visible )); then printf '\n' >&2; fi
else
  if (( progress_visible )); then printf '\n' >&2; fi
  fail "Conversion failed."
fi

mv -n "$temp_dir/video.mp4" "$output"
[[ ! -e "$temp_dir/video.mp4" ]] || fail "Output already exists: $output"
if (( progress_visible )); then
  printf 'Converting [##############################] 100%%\n' >&2
fi
printf 'Created %s\n' "$output"
