#!/usr/bin/env sh
# Run by xdg-desktop-portal-termfilechooser for every file dialog (arguments
# are described in xdg-desktop-portal-termfilechooser(5)): opens yazi in the
# terminal given by TERMCMD and writes the chosen path(s) to $out.
#
# Based on the yazi-wrapper.sh shipped with termfilechooser; the keys below
# come from the chooser yazi plugin (~/.config/yazi/plugins/chooser.yazi,
# bound in keymap.toml), which sees the dialog through TERMFILECHOOSER_MODE.
#
# Saving: the file to be saved is shown hovered in its folder, as a
# placeholder (holding one line that says so) that is removed again before
# the app writes the real file. It follows you to every folder you open (the
# chooser plugin's setup moves it, keeping a name given with r).
#   Ctrl+S  save here, under the suggested name (name_1, name_2, ... if taken)
#   r       rename the placeholder, then Ctrl+S: save under that name
#   a       type a name (or a path), Enter: save under it; "name/" creates
#           that folder instead
#   o/Enter on an existing file: save over it
#   q, Esc  cancel
#
# Open/upload: o on a file picks it; when the app accepts several files, o
# picks every file selected with Space (otherwise the first one). Enter only
# picks the hovered file and enters folders (it runs the smart-enter plugin).
# When the app asks for a folder, Ctrl+S in it or o on it. q, Esc cancel.

multiple="$1"
directory="$2"
save="$3"
path="$4" # suggested file (save) or starting folder (open)
out="$5"  # where the chosen paths go, one per line
debug="$6"
shift 6 # the rest is TERMCMD, split into words

set -e
if [ "$debug" = 1 ]; then
    set -x
fi

# termfilechooser escapes every ' in the path as '\'' (for a shell that it no
# longer runs the wrapper through); undo that.
path="$(printf '%s' "$path" | sed "s/'\\\\''/'/g")"

# yazi writes the folder it was quit from here (Ctrl+S, and cancel too, for
# the cleanup), the chooser plugin a typed file name, a cancel flag and where
# the save placeholder is now (it follows the current folder). Never trust
# leftovers. The save placeholder is removed on exit too, wherever it went, as
# long as it still is one.
cwd_file="$out.1"
save_as="$out.2"
cancel_file="$out.3"
state_file="$out.4"
placeholder=""
moved=""
start_folder=""
marker="The file will be saved here (xdg-desktop-portal-termfilechooser)."
rm -f "$cwd_file" "$save_as" "$cancel_file" "$state_file"
cleanup() {
    remove_placeholders "$placeholder" "$moved"
    sweep_placeholders "$start_folder" "$(final_dir)"
    rm -f "$cwd_file" "$save_as" "$cancel_file" "$state_file"
}
trap cleanup EXIT
# Killed (the app cancelled the dialog, the session ends): clean up too.
trap 'exit 1' HUP INT TERM

# current_placeholder -- where the chooser plugin last put the placeholder
# (first line of its state file; empty when there is none right now).
current_placeholder() {
    if [ -s "$state_file" ]; then
        head -n 1 "$state_file"
    fi
}

# sweep_placeholders DIR... -- remove every placeholder directly in DIRs,
# also ones the plugin lost track of (renamed by another program, say).
sweep_placeholders() {
    for d in "$@"; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        find "$d" -maxdepth 1 -type f -size -200c -print 2>/dev/null | while IFS= read -r f; do
            if is_placeholder "$f"; then
                rm -f "$f"
            fi
        done
    done
}

# remove_placeholders [FILE...] -- remove FILEs and every placeholder the
# plugin recorded (its current one and any copies), each only while it still
# is a placeholder: a real file put under its name stays.
remove_placeholders() {
    {
        for p in "$@"; do printf '%s\n' "$p"; done
        [ -f "$state_file" ] && cat "$state_file"
    } | while IFS= read -r p; do
        if [ -n "$p" ] && is_placeholder "$p"; then
            rm -f "$p"
        fi
    done
}

# is_placeholder FILE -- a regular file holding just the marker line.
is_placeholder() {
    [ -f "$1" ] && [ "$(head -c 200 "$1")" = "$marker" ]
}

# start_dir PATH -- the folder to start in: PATH if it is one, else its parent
# (PATH is a file, or doesn't exist yet), else $HOME.
start_dir() {
    if [ -d "$1" ]; then
        printf '%s\n' "$1"
    elif [ -d "$(dirname "$1")" ]; then
        dirname "$1"
    else
        printf '%s\n' "$HOME"
    fi
}

# First chosen path: an opened entry, else the folder yazi was quit from
# (Ctrl+S); nothing when cancelled.
chosen_path() {
    if [ -e "$cancel_file" ]; then
        :
    elif [ -s "$out" ]; then
        head -n 1 "$out"
    elif [ -s "$cwd_file" ]; then
        head -n 1 "$cwd_file"
    fi
}

# The folder yazi ended in, whatever the outcome ("" if unknown).
final_dir() {
    if [ -s "$cwd_file" ]; then
        head -n 1 "$cwd_file"
    fi
}

# unique_path DIR NAME -- DIR/NAME, or DIR/NAME_1, DIR/NAME_2, ... if it
# exists (the extension stays last), like termfilechooser's own placeholders.
unique_path() {
    dir=${1%/}
    name=$2
    if [ ! -e "$dir/$name" ] && [ ! -L "$dir/$name" ]; then
        printf '%s/%s\n' "$dir" "$name"
        return
    fi
    stem=${name%.*}
    ext=${name##*.}
    if [ "$stem" = "$name" ] || [ -z "$stem" ]; then
        stem=$name
        ext=""
    else
        ext=".$ext"
    fi
    i=1
    while [ -e "$dir/${stem}_$i$ext" ] || [ -L "$dir/${stem}_$i$ext" ]; do
        i=$((i + 1))
    done
    printf '%s/%s_%s%s\n' "$dir" "$stem" "$i" "$ext"
}

# find_placeholder DIR... -- where the placeholder is now (it may have been
# renamed, moved or copied in yazi): the first file in the first DIR that
# holds just the marker line. By content, so a copy (another inode, as a
# move to another filesystem also is) counts too.
find_placeholder() {
    for d in "$@"; do
        [ -d "$d" ] || continue
        find "$d" -maxdepth 1 -type f -size -200c -print 2>/dev/null | while IFS= read -r f; do
            if is_placeholder "$f"; then
                printf '%s\n' "$f"
                break
            fi
        done | head -n 1 | grep . && return
    done
    return 0
}

if [ "$save" = 1 ]; then
    name="$(basename "$path")"
    if [ -f "$path" ]; then
        start="$path" # an existing file: hover it (o saves over it)
        start_folder="$(dirname "$path")"
    else
        # The file to be saved, hovered: a placeholder (unique name, also
        # when a folder of the suggested name exists).
        start="$(unique_path "$(start_dir "$(dirname "$path")")" "$name")"
        start_folder="$(dirname "$start")"
        if printf '%s\n' "$marker" 2>/dev/null >"$start"; then
            placeholder="$start"
        else
            start="$start_folder" # read-only folder: no placeholder
        fi
    fi
    TERMFILECHOOSER_MODE=save TERMFILECHOOSER_CANCEL="$cancel_file" \
        TERMFILECHOOSER_SAVE_AS="$save_as" TERMFILECHOOSER_NAME="$name" \
        TERMFILECHOOSER_PLACEHOLDER="$placeholder" TERMFILECHOOSER_DIR="$start_folder" \
        TERMFILECHOOSER_STATE="$state_file" TERMFILECHOOSER_MARKER="$marker" \
        "$@" yazi --chooser-file="$out" --cwd-file="$cwd_file" "$start"
    chosen="$(chosen_path)"

    # The placeholder's current place names the file (it follows the folder
    # and may have been renamed): as the plugin last recorded it (it also
    # makes one when there was none, e.g. after leaving the folder of an
    # existing file), else searched for (plugin not set up). The cleanup on
    # exit removes it and any other placeholder (only while it still is the
    # marker file: a real file put under its name stays), then the app writes
    # the real file.
    current="$(current_placeholder)"
    if [ -n "$current" ] && is_placeholder "$current"; then
        moved="$current"
    elif [ -n "$placeholder" ]; then
        moved="$(find_placeholder "$(dirname "$placeholder")" "$(final_dir)" "$chosen" "$(dirname "${chosen:-/}")")"
    fi

    if [ -s "$save_as" ]; then
        typed="$(head -n 1 "$save_as")"
        if [ -d "$typed" ]; then
            # An existing folder: save in it, suggested name.
            unique_path "$typed" "$name" >"$out"
        else
            # A typed name is used as is, also over an existing file.
            printf '%s\n' "$typed" >"$out"
        fi
    elif [ -z "$chosen" ]; then
        : # cancelled
    elif [ -d "$chosen" ]; then
        # Ctrl+S in a folder: the placeholder in it (renamed/moved there), else
        # the suggested name.
        if [ -n "$moved" ] && [ "$(dirname "$moved")" = "${chosen%/}" ]; then
            printf '%s\n' "$moved" >"$out"
        else
            unique_path "$chosen" "$name" >"$out"
        fi
    else
        # An opened file (the placeholder, or an existing one to save over),
        # one even if several were selected (the portal rejects more).
        printf '%s\n' "$chosen" >"$out"
    fi
elif [ "$directory" = 1 ]; then
    TERMFILECHOOSER_MODE=dir TERMFILECHOOSER_CANCEL="$cancel_file" \
        "$@" yazi --chooser-file="$out" --cwd-file="$cwd_file" "$(start_dir "$path")"
    chosen="$(chosen_path)"
    if [ -n "$chosen" ]; then
        # A file opened by mistake means its folder.
        if [ ! -d "$chosen" ]; then
            chosen="$(dirname "$chosen")"
        fi
        printf '%s\n' "$chosen" >"$out"
    fi
else
    TERMFILECHOOSER_MODE=open TERMFILECHOOSER_CANCEL="$cancel_file" \
        "$@" yazi --chooser-file="$out" "$(start_dir "$path")"
    # yazi writes every selected entry, folders included (o on a folder):
    # keep the files, and only the first unless several were asked for.
    # yazi ends the list without a newline, which makes read fail on the last
    # entry while still filling in $f: hence the [ -n "$f" ].
    if [ -e "$cancel_file" ]; then
        : >"$out"
    elif [ -s "$out" ]; then
        files="$(while IFS= read -r f || [ -n "$f" ]; do [ -d "$f" ] || printf '%s\n' "$f"; done <"$out")"
        if [ "$multiple" != 1 ]; then
            files="$(printf '%s\n' "$files" | head -n 1)"
        fi
        if [ -n "$files" ]; then
            printf '%s\n' "$files" >"$out"
        else
            : >"$out"
        fi
    fi
fi
