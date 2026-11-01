#!/bin/zsh
set -euo pipefail

if (( $# < 1 || $# > 2 )); then
  print -u2 "usage: $0 <recordings-directory> [output-directory]"
  exit 64
fi

recordings_dir=$1
script_dir=${0:A:h}
output_dir=${2:-${script_dir:h}/dist/assets/media}
work_dir=$(mktemp -d /tmp/ilaunchpad-showcase.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT

for recording in 拖动调换.mov 滑动.mov app组开合.mov 搜索.mov 长按抖动.mov; do
  if [[ ! -f "$recordings_dir/$recording" ]]; then
    print -u2 "missing recording: $recordings_dir/$recording"
    exit 66
  fi
done

mkdir -p "$output_dir"

make_shot() {
  local input=$1
  local start=$2
  local duration=$3
  local peak_zoom=$4
  local focus_x=$5
  local focus_y=$6
  local output=$7
  local frames=$(awk -v value="$duration" 'BEGIN { printf "%d", value * 60 + 0.5 }')
  local ramp=54
  local zoom_delta=$(awk -v value="$peak_zoom" 'BEGIN { printf "%.4f", value - 1 }')
  local zoom_expression="1+${zoom_delta}*(1-cos(PI*clip(on/${ramp},0,1)))/2*(1-(1-cos(PI*clip((on-(${frames}-${ramp}))/${ramp},0,1)))/2)"

  ffmpeg -hide_banner -loglevel error -y \
    -ss "$start" -t "$duration" -i "$input" \
    -vf "fps=60,zoompan=z='${zoom_expression}':x='clip(${focus_x}-iw/(2*zoom),0,iw-iw/zoom)':y='clip(${focus_y}-ih/(2*zoom),0,ih-ih/zoom)':d=1:s=1920x1248:fps=60,setsar=1,format=yuv420p" \
    -an -c:v libx264 -preset fast -crf 12 -movflags +faststart "$output"
}

# Each shot starts and ends at a full-frame composition. The camera only
# moves toward the part of the real recording where the active gesture occurs.
make_shot "$recordings_dir/滑动.mov"      1.0 5.5 1.06 1800 1260 "$work_dir/01-pages.mp4"
make_shot "$recordings_dir/搜索.mov"      0.8 5.5 1.22 1050  430 "$work_dir/02-search.mp4"
make_shot "$recordings_dir/拖动调换.mov"  2.5 6.5 1.22 2050  760 "$work_dir/03-drag.mp4"
make_shot "$recordings_dir/app组开合.mov" 0.5 8.0 1.20 1800 1280 "$work_dir/04-folder.mp4"
make_shot "$recordings_dir/长按抖动.mov"  1.7 4.4 1.12 1880 1060 "$work_dir/05-edit.mp4"

ffmpeg -hide_banner -loglevel error -y \
  -i "$work_dir/01-pages.mp4" -i "$work_dir/02-search.mp4" -i "$work_dir/03-drag.mp4" \
  -i "$work_dir/04-folder.mp4" -i "$work_dir/05-edit.mp4" \
  -filter_complex "[0:v][1:v]xfade=transition=fade:duration=0.35:offset=5.15[x1];[x1][2:v]xfade=transition=fade:duration=0.35:offset=10.30[x2];[x2][3:v]xfade=transition=fade:duration=0.35:offset=16.45[x3];[x3][4:v]xfade=transition=fade:duration=0.35:offset=24.10,format=yuv420p[v]" \
  -map "[v]" -an -r 60 -c:v libx264 -profile:v high -level 5.1 -preset slow -crf 22 \
  -movflags +faststart "$output_dir/hero-demo.mp4"

ffmpeg -hide_banner -loglevel error -y \
  -i "$work_dir/03-drag.mp4" -i "$work_dir/04-folder.mp4" -i "$work_dir/05-edit.mp4" \
  -filter_complex "[0:v][1:v]xfade=transition=fade:duration=0.35:offset=6.15[x1];[x1][2:v]xfade=transition=fade:duration=0.35:offset=13.80,format=yuv420p[v]" \
  -map "[v]" -an -r 60 -c:v libx264 -profile:v high -level 5.1 -preset slow -crf 18 \
  -movflags +faststart "$output_dir/interaction.mp4"

ffmpeg -hide_banner -loglevel error -y -i "$output_dir/hero-demo.mp4" -an \
  -c:v libvpx-vp9 -b:v 0 -crf 35 -row-mt 1 -cpu-used 4 -deadline good \
  "$output_dir/hero-demo.webm"
ffmpeg -hide_banner -loglevel error -y -i "$output_dir/interaction.mp4" -an \
  -c:v libvpx-vp9 -b:v 0 -crf 30 -row-mt 1 -cpu-used 4 -deadline good \
  "$output_dir/interaction.webm"

print "created: $output_dir/hero-demo.mp4"
print "created: $output_dir/hero-demo.webm"
print "created: $output_dir/interaction.mp4"
print "created: $output_dir/interaction.webm"
