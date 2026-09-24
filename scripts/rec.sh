#!/usr/bin/env bash
set -euo pipefail

# rec.sh — screen / webcam recorder and mic+camera tester built on ffmpeg.
# Targets X11 (x11grab), PipeWire/Pulse audio, V4L2 webcams, VAAPI encoding.
#
# Commands:
#   screen      record the screen (default when run with only options)
#   cam         record the screen with the webcam as picture-in-picture
#   webcam      record the webcam only
#   test        show the webcam with a live mic level meter (no file written)
#   stop        stop the running recording
#   toggle      start a screen recording if idle, otherwise stop  (for a keybinding)
#   status      one-line status for xmobar/polybar: "● REC 01:23", or nothing
#   devices     list cameras and audio sources
#   menu        interactive fzf menu (default when run with no args)
#
# Options for screen / cam / webcam:
#   -a, --audio MODE     none | mic | sys | both        (default: mic)
#   -m, --mic SRC        pulse source to use as mic     (default: system default)
#   -f, --fps N          frame rate                      (default: 30)
#   -s, --scale H        downscale output to height H, e.g. 1080 (default: native)
#   -c, --camera DEV     webcam device                   (default: /dev/video0)
#       --cam-size WxH   webcam capture size             (default: 1280x720)
#       --pip-width N    PiP width in px                 (default: screen width / 6)
#       --pip-pos POS    br | bl | tr | tl               (default: br)
#       --no-flip        do not mirror the webcam image
#       --sw             force software x264 (VAAPI is used automatically for outputs <= 1080p)
#   -o, --output FILE    output path                     (default: $REC_DIR/<mode>-<timestamp>.mp4)
#   -d, --delay N        countdown N seconds before starting
#   -b, --background     return immediately instead of waiting (implied without a tty)
#
# Options for test:
#   -l, --listen         also play the mic back to the default output (use headphones!)
#
# Environment: REC_DIR (default ~/Videos/recordings), VAAPI_MAX_H (default 1080)

REC_DIR="${REC_DIR:-$HOME/Videos/recordings}"
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}"
PID_FILE="$RUN_DIR/rec.pid"
INFO_FILE="$RUN_DIR/rec.info"
LOG_FILE="$RUN_DIR/rec.log"
ENC_CACHE="$RUN_DIR/rec.encoder"
export DISPLAY="${DISPLAY:-:0}"

# ---- defaults ---------------------------------------------------------------
AUDIO=mic
MIC=default
FPS=30
SCALE=""
CAMERA=/dev/video0
CAM_SIZE=1280x720
PIP_WIDTH=""
PIP_POS=br
FLIP=1
FORCE_SW=0
LISTEN=0
OUTPUT=""
DELAY=0
BACKGROUND=0

# ---- helpers ----------------------------------------------------------------
die()    { printf 'rec: %s\n' "$*" >&2; exit 1; }
notify() { command -v notify-send >/dev/null && notify-send -a rec "$@" || true; }
has_tty(){ [[ -t 1 ]]; }

usage() { sed -n '/^# rec\.sh /,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

# Kernel start time of a process (jiffies since boot); with the pid it identifies a process
# uniquely even after pids are recycled.
proc_start() { cut -d')' -f2 "/proc/$1/stat" 2>/dev/null | awk '{print $20}'; }

# Lock file holds "<pid> <start-time> <state>", state = countdown | recording | stopping.
# Writes go through a temp file + mv so a concurrent `rec.sh status` never sees a torn file.
atomic_write() { local f="$1"; shift; printf '%s\n' "$@" > "$f.tmp" && mv -f "$f.tmp" "$f"; }
write_lock()   { atomic_write "$PID_FILE" "$1 $(proc_start "$1") $2"; }
lock_state()   { awk '{print $3}' "$PID_FILE" 2>/dev/null || true; }
release_lock() { [[ $(cut -d' ' -f1 "$PID_FILE" 2>/dev/null) == "$1" ]] && rm -f "$PID_FILE" "$INFO_FILE"; return 0; }

# Prints the pid holding the lock if that process is still alive; clears a stale lock.
running_pid() {
    local pid start state
    [[ -f "$PID_FILE" ]] || return 1
    read -r pid start state < "$PID_FILE" || true
    if [[ -n "$pid" && -n "$start" ]] && kill -0 "$pid" 2>/dev/null \
       && [[ $(proc_start "$pid") == "$start" ]]; then
        echo "$pid"
    else
        rm -f "$PID_FILE" "$INFO_FILE"
        return 1
    fi
}

refuse_if_running() {
    running_pid >/dev/null && die "a recording is already running (pid $(cut -d' ' -f1 "$PID_FILE")); use 'rec.sh stop'"
    return 0
}

screen_geometry() {
    # prints "W H" of the whole X screen
    local dims
    dims=$(xdpyinfo -display "$DISPLAY" 2>/dev/null | awk '/dimensions:/ {print $2}')
    [[ -n $dims ]] || die "cannot query the X screen on DISPLAY=$DISPLAY"
    echo "$(even "${dims%x*}") $(even "${dims#*x}")"
}

even() { echo $(( $1 - ($1 % 2) )); }

# Decide on the video encoder once per session and cache it.
pick_encoder() {
    if (( FORCE_SW )); then echo sw; return; fi
    if [[ -f "$ENC_CACHE" ]]; then cat "$ENC_CACHE"; return; fi
    local enc=sw
    if [[ -e /dev/dri/renderD128 ]] && ffmpeg -hide_banner -loglevel quiet -f lavfi -i color=size=256x256:rate=30 -frames:v 2 \
         -vaapi_device /dev/dri/renderD128 -vf 'format=nv12,hwupload' -c:v h264_vaapi -f null - 2>/dev/null; then
        enc=vaapi
    fi
    echo "$enc" | tee "$ENC_CACHE"
}

default_sink()   { pactl get-default-sink; }
default_source() { pactl get-default-source; }

# pulse silently accepts unknown source names (and records nothing), so validate ours.
check_source() {
    [[ $1 == default ]] && return 0
    pactl list short sources | awk '{print $1; print $2}' | grep -qxF -- "$1" \
        || die "audio source '$1' not found (see 'rec.sh devices')"
}

# Appends ffmpeg audio input args to INPUTS and the audio filter/map to AFILTER / AMAP.
# Uses global input counter N (next free input index).
add_audio() {
    case "$AUDIO" in
        none) AMAP=() ;;
        mic|sys)
            local src="$MIC"; [[ $AUDIO == sys ]] && src="$(default_sink).monitor"
            check_source "$src"
            INPUTS+=(-thread_queue_size 1024 -f pulse -i "$src")
            AFILTER="[$N:a]aresample=async=1[a]"
            AMAP=(-map "[a]" -c:a aac -b:a 160k); N=$((N+1)) ;;
        both)
            check_source "$MIC"
            INPUTS+=(-thread_queue_size 1024 -f pulse -i "$MIC")
            INPUTS+=(-thread_queue_size 1024 -f pulse -i "$(default_sink).monitor")
            AFILTER="[$N:a]aresample=async=1[am];[$((N+1)):a]aresample=async=1[as];[am][as]amix=inputs=2:duration=longest:normalize=0[a]"
            AMAP=(-map "[a]" -c:a aac -b:a 192k); N=$((N+2)) ;;
        *) die "unknown audio mode '$AUDIO' (none|mic|sys|both)" ;;
    esac
}

# Video encoder args + tail of the video filter chain, chosen for the output height.
# The Radeon VAAPI encoder only keeps up to ~1080p at 30 fps; above that x264 ultrafast is used.
VAAPI_MAX_H=${VAAPI_MAX_H:-1080}
encoder_args() {
    local out_h="$1"
    [[ -n "$SCALE" ]] && out_h="$SCALE"
    ENC=sw
    [[ $(pick_encoder) == vaapi && $out_h -le $VAAPI_MAX_H ]] && ENC=vaapi
    if [[ $ENC == vaapi ]]; then
        VPRE=(-vaapi_device /dev/dri/renderD128)
        VTAIL="format=nv12,hwupload"
        [[ -n "$SCALE" ]] && VTAIL+=",scale_vaapi=w=-2:h=$SCALE"
        VENC=(-c:v h264_vaapi -qp 22 -bf 0)
    else
        VPRE=()
        VTAIL="format=yuv420p"
        [[ -n "$SCALE" ]] && VTAIL="scale=-2:$SCALE,$VTAIL"
        VENC=(-c:v libx264 -preset ultrafast -crf 22)
    fi
}

countdown() {
    local i
    for (( i=DELAY; i>0; i-- )); do
        printf '\rStarting in %d... ' "$i"; notify "Recording starts in $i" -t 900; sleep 1
    done
    (( DELAY > 0 )) && printf '\r%-30s\r' ""
    return 0
}

# Interrupt handler while starting/recording in the foreground.
FF_PID=""
on_interrupt() {
    trap '' INT TERM     # a second Ctrl+C must not reach ffmpeg a second time
    echo
    if [[ -n "$FF_PID" ]]; then
        do_stop; exit 0
    fi
    # ffmpeg may have been spawned but not yet registered: catch it by parent pid
    pkill -INT -P $$ -x ffmpeg 2>/dev/null && { sleep 1; }
    release_lock $$
    exit 130
}

# start_ffmpeg MODE ARGS... — launches ffmpeg detached, records pid, waits if interactive.
start_ffmpeg() {
    local mode="$1"; shift
    refuse_if_running
    [[ -n "$OUTPUT" ]] || OUTPUT="$REC_DIR/$mode-$(date +%Y-%m-%d_%H-%M-%S).mp4"
    mkdir -p "$(dirname "$OUTPUT")"

    # Hold the lock with our own pid during the countdown so a second start (e.g. the
    # toggle key) is refused; an interrupt before ffmpeg is registered just releases it.
    write_lock $$ countdown
    trap on_interrupt INT TERM
    countdown

    setsid ffmpeg -hide_banner -loglevel warning -nostdin -y "$@" -movflags +faststart "$OUTPUT" \
        </dev/null >"$LOG_FILE" 2>&1 &
    FF_PID=$!
    write_lock "$FF_PID" recording
    atomic_write "$INFO_FILE" "$OUTPUT" "$(date +%s)"

    sleep 1.5
    if ! kill -0 "$FF_PID" 2>/dev/null; then
        trap - INT TERM
        release_lock "$FF_PID"
        echo "ffmpeg failed to start:" >&2; tail -n 15 "$LOG_FILE" >&2
        notify -u critical "Recording failed" "$(tail -n 3 "$LOG_FILE")"
        exit 1
    fi
    notify "● Recording ($mode)" "$(basename "$OUTPUT")" -t 2500
    echo "● Recording ($mode, ${ENC:-?} encoder) → $OUTPUT"

    if (( BACKGROUND )) || ! has_tty; then
        trap - INT TERM
        echo "  stop with: rec.sh stop"
        return 0
    fi

    local start=$SECONDS
    echo "  Ctrl+C or 'rec.sh stop' to finish"
    while kill -0 "$FF_PID" 2>/dev/null; do
        printf '\r  ● %02d:%02d ' $(( (SECONDS-start)/60 )) $(( (SECONDS-start)%60 ))
        sleep 1
    done
    trap - INT TERM
    printf '\n'
    # ffmpeg exits 255 after a signal-driven (clean) stop, so judge by the file, not the code.
    local rc=0; wait "$FF_PID" || rc=$?
    release_lock "$FF_PID"
    if ! ffprobe -v error "$OUTPUT" >/dev/null 2>&1; then
        echo "recording failed (ffmpeg exit $rc, file unreadable):" >&2; tail -n 10 "$LOG_FILE" >&2
        notify -u critical "Recording failed" "$(basename "$OUTPUT")"
        exit 1
    fi
    echo "Saved: $OUTPUT"
}

do_stop() {
    local pid out state
    pid=$(running_pid) || { echo "no recording running"; return 0; }
    state=$(lock_state)
    case "$state" in
        countdown)
            # cancel the rec.sh that is counting down (TERM: a backgrounded bash ignores INT)
            kill -TERM "$pid" 2>/dev/null || true
            sleep 0.3
            release_lock "$pid"
            echo "countdown cancelled"
            return 0 ;;
        recording)
            # One INT makes ffmpeg finish cleanly; a second would abort and corrupt the file,
            # so mark the lock as stopping before signalling and never signal twice.
            write_lock "$pid" stopping
            kill -INT "$pid" 2>/dev/null || true ;;
        stopping)
            echo "already stopping, waiting for ffmpeg to finish writing..." ;;
        *)  die "unexpected lock state '$state'" ;;
    esac
    out=$(head -n1 "$INFO_FILE" 2>/dev/null || true)
    # Finalizing (faststart moves the index) can take a while on long recordings, so wait.
    local i
    for (( i=0; i<3000; i++ )); do
        kill -0 "$pid" 2>/dev/null || break
        (( i == 25 )) && { echo "finalizing $(basename "$out") ..."; notify "Finalizing recording..." -t 2000; }
        sleep 0.2
    done
    if kill -0 "$pid" 2>/dev/null; then
        echo "ffmpeg (pid $pid) is still finalizing after 10 minutes; not killing it" >&2
        return 1
    fi
    release_lock "$pid"
    notify "■ Recording saved" "$(basename "$out")" -t 3000
    echo "Saved: $out"
}

do_status() {
    local pid start
    pid=$(running_pid) || exit 0
    case "$(lock_state)" in
        countdown) echo "● REC starting"; exit 0 ;;
        stopping)  echo "■ REC saving";   exit 0 ;;
    esac
    start=$(sed -n 2p "$INFO_FILE" 2>/dev/null)
    [[ $start =~ ^[0-9]+$ ]] || exit 0
    local el=$(( $(date +%s) - start ))
    printf '● REC %02d:%02d\n' $(( el/60 )) $(( el%60 ))
}

do_devices() {
    echo "Cameras:"
    local d
    for d in /dev/video*; do
        [[ -e $d ]] || continue
        local name; name=$(cat "/sys/class/video4linux/$(basename "$d")/name" 2>/dev/null || echo "?")
        # only devices that expose capture formats are usable
        if ffmpeg -hide_banner -f v4l2 -list_formats all -i "$d" 2>&1 | grep -q "Raw\|Compressed"; then
            printf '  %-14s %s\n' "$d" "$name"
        fi
    done
    echo
    echo "Audio sources (mic / monitors):    * = default"
    local def; def=$(default_source)
    pactl list short sources | awk -v def="$def" '{m = ($2==def) ? "*" : " "; printf "  %s %s\n", m, $2}'
    echo
    echo "Default sink: $(default_sink)"
    if [[ $(pick_encoder) == vaapi ]]; then
        echo "Encoder:      VAAPI (outputs up to ${VAAPI_MAX_H}p), x264 ultrafast above that"
    else
        echo "Encoder:      x264 ultrafast (VAAPI unavailable)"
    fi
}

# ---- recording modes ----------------------------------------------------------
cam_input()   { echo -thread_queue_size 1024 -f v4l2 -input_format mjpeg -video_size "$CAM_SIZE" -framerate "$FPS" -i "$CAMERA"; }
flip_filter() { (( FLIP )) && echo "hflip," || true; }

# rec_screen [pip] — the whole screen, optionally with the webcam overlaid.
rec_screen() {
    local pip=${1:-} w h mode=screen
    refuse_if_running
    read -r w h < <(screen_geometry)
    encoder_args "$h"
    INPUTS=(-thread_queue_size 1024 -probesize 32 -f x11grab -framerate "$FPS" -video_size "${w}x${h}" -i "$DISPLAY+0,0")
    N=1; AFILTER=""; AMAP=()
    local fc="[0:v]$VTAIL[v]"
    if [[ -n $pip ]]; then
        mode=cam
        [[ -n "$PIP_WIDTH" ]] || PIP_WIDTH=$(even $(( w / 6 )))
        local pos
        case "$PIP_POS" in
            br) pos="W-w-40:H-h-40" ;; bl) pos="40:H-h-40" ;;
            tr) pos="W-w-40:40"     ;; tl) pos="40:40" ;;
            *) die "bad --pip-pos '$PIP_POS' (br|bl|tr|tl)" ;;
        esac
        INPUTS+=($(cam_input)); N=2
        fc="[1:v]$(flip_filter)scale=$PIP_WIDTH:-2[pip];[0:v][pip]overlay=$pos,$VTAIL[v]"
    fi
    add_audio
    [[ -n "$AFILTER" ]] && fc+=";$AFILTER"
    start_ffmpeg "$mode" "${VPRE[@]}" "${INPUTS[@]}" -filter_complex "$fc" -map "[v]" "${VENC[@]}" "${AMAP[@]}"
}

rec_cam() { rec_screen pip; }

rec_webcam() {
    refuse_if_running
    encoder_args "${CAM_SIZE#*x}"
    INPUTS=($(cam_input))
    N=1; AFILTER=""; AMAP=()
    add_audio
    local fc="[0:v]$(flip_filter)$VTAIL[v]"
    [[ -n "$AFILTER" ]] && fc+=";$AFILTER"
    start_ffmpeg webcam "${VPRE[@]}" "${INPUTS[@]}" -filter_complex "$fc" -map "[v]" "${VENC[@]}" "${AMAP[@]}"
}

# Camera + mic check in an XVideo window (SDL output does not render on every setup).
do_test() {
    local mic="$MIC"; LOOP_PID=""
    [[ $mic == default ]] && mic=$(default_source)
    check_source "$mic"
    local w=${CAM_SIZE%x*} flip; flip=$(flip_filter)
    echo "Camera: $CAMERA ($CAM_SIZE)"
    echo "Mic:    $mic"
    echo "Speak — the bar at the bottom should move (green ok, yellow loud, red clipping)."
    echo "Ctrl+C here to quit."
    if (( LISTEN )); then
        command -v pw-loopback >/dev/null || die "--listen needs pw-loopback (PipeWire)"
        pw-loopback --capture="$mic" --playback="$(default_sink)" &
        LOOP_PID=$!
        trap '[[ -n "$LOOP_PID" ]] && kill "$LOOP_PID" 2>/dev/null' EXIT
        sleep 0.5
        kill -0 "$LOOP_PID" 2>/dev/null || die "pw-loopback failed to start"
        echo "Listening enabled: mic is being played back to $(default_sink)"
    fi
    local label="Camera: $CAMERA   Mic: $mic"
    label=${label//\\/\\\\}; label=${label//:/\\:}; label=${label//,/\\,}; label=${label//\'/}
    local color='if(gte(VOLUME\,-3)\,0xff4040ff\,if(gte(VOLUME\,-15)\,0xff40e0ff\,0xff40ff40))'
    ffmpeg -hide_banner -loglevel error -nostdin \
        $(cam_input) \
        -thread_queue_size 1024 -f pulse -i "$mic" \
        -filter_complex "[0:v]${flip}drawtext=text='$label':x=12:y=12:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=6[cam];\
[1:a]showvolume=w=$((w-40)):h=36:b=4:f=0.92:t=1:v=1:dm=2:c=$color,format=rgba[vol];\
[cam][vol]overlay=20:H-h-20,format=yuv420p[out]" \
        -map "[out]" -f xv "rec test" || true
}

do_menu() {
    local choices=(
        "Screen  (mic)"
        "Screen  (no audio)"
        "Screen  (system audio)"
        "Screen  (mic + system audio)"
        "Screen + webcam  (mic)"
        "Screen + webcam  (system audio)"
        "Screen + webcam  (mic + system audio)"
        "Webcam only  (mic)"
        "Test mic & camera"
        "Stop recording"
        "List devices"
    )
    local pick
    if command -v fzf >/dev/null; then
        pick=$(printf '%s\n' "${choices[@]}" | fzf --prompt="rec ▸ " --height=~50% --reverse --header="$(do_status || true)") || exit 0
    else
        select pick in "${choices[@]}"; do break; done
    fi
    case "$pick" in
        "Screen  (mic)")                          AUDIO=mic;  rec_screen ;;
        "Screen  (no audio)")                     AUDIO=none; rec_screen ;;
        "Screen  (system audio)")                 AUDIO=sys;  rec_screen ;;
        "Screen  (mic + system audio)")           AUDIO=both; rec_screen ;;
        "Screen + webcam  (mic)")                 AUDIO=mic;  rec_cam ;;
        "Screen + webcam  (system audio)")        AUDIO=sys;  rec_cam ;;
        "Screen + webcam  (mic + system audio)")  AUDIO=both; rec_cam ;;
        "Webcam only  (mic)")                     AUDIO=mic;  rec_webcam ;;
        "Test mic & camera")                      do_test ;;
        "Stop recording")                         do_stop ;;
        "List devices")                           do_devices ;;
        *) exit 0 ;;
    esac
}

# ---- argument parsing ----------------------------------------------------------
CMD=""
OPTS=0   # set when any option was given, so bare options mean "screen"
need() { [[ $# -ge 2 && -n "$2" ]] || die "$1 requires a value (see --help)"; }
num()  { need "$@"; [[ $2 =~ ^[0-9]+$ ]] || die "$1 expects a whole number, got '$2'"; }
while (( $# )); do
    case "$1" in
        screen|cam|webcam|test|stop|toggle|status|devices|menu) CMD="$1"; shift; continue ;;
        -a|--audio)     need "$@"; AUDIO="$2"; shift ;;
        -m|--mic)       need "$@"; MIC="$2"; shift ;;
        -f|--fps)       num "$@"; FPS="$2"; shift ;;
        -s|--scale)     num "$@"; SCALE=$(even "$2"); shift ;;
        -c|--camera)    need "$@"; CAMERA="$2"; shift ;;
        --cam-size)     need "$@"; [[ $2 =~ ^[0-9]+x[0-9]+$ ]] || die "--cam-size expects WxH"; CAM_SIZE="$2"; shift ;;
        --pip-width)    num "$@"; PIP_WIDTH="$2"; shift ;;
        --pip-pos)      need "$@"; PIP_POS="$2"; shift ;;
        --no-flip)      FLIP=0 ;;
        --sw)           FORCE_SW=1 ;;
        -o|--output)    need "$@"; OUTPUT="$2"; shift ;;
        -d|--delay)     num "$@"; DELAY="$2"; shift ;;
        -b|--background) BACKGROUND=1 ;;
        -l|--listen)    LISTEN=1 ;;
        -h|--help)      usage; exit 0 ;;
        *) die "unknown argument '$1' (see --help)" ;;
    esac
    OPTS=1
    shift
done

for t in ffmpeg pactl; do command -v "$t" >/dev/null || die "missing dependency: $t"; done
case "$CMD" in screen|cam|test|toggle|menu|"")
    command -v xdpyinfo >/dev/null || die "missing dependency: xdpyinfo (x11-utils)" ;;
esac

case "$CMD" in
    screen)  rec_screen ;;
    cam)     rec_cam ;;
    webcam)  rec_webcam ;;
    test)    do_test ;;
    stop)    do_stop ;;
    toggle)  if running_pid >/dev/null; then do_stop; else BACKGROUND=1; rec_screen; fi ;;
    status)  do_status ;;
    devices) do_devices ;;
    menu)    do_menu ;;
    "")      if (( OPTS )); then rec_screen; else do_menu; fi ;;
esac
