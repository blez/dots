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
# the app writes the real file.
#   Ctrl+S  save here, under the suggested name (name_1, name_2, ... if taken)
#   r       rename the placeholder, then Ctrl+S: save under that name
#   x, p    move the placeholder to another folder, then Ctrl+S there
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
# the cleanup), the chooser plugin a typed file name and a cancel flag. Never
# trust leftovers. The save placeholder is removed on exit too, as long as it
# still is one.
cwd_file="$out.1"
save_as="$out.2"
cancel_file="$out.3"
placeholder=""
marker="The file will be saved here (xdg-desktop-portal-termfilechooser)."
rm -f "$cwd_file" "$save_as" "$cancel_file"
trap 'rm -f "$cwd_file" "$save_as" "$cancel_file"; [ -n "$placeholder" ] && is_placeholder "$placeholder" && rm -f "$placeholder"' EXIT

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
    else
        # The file to be saved, hovered: a placeholder (unique name, also
        # when a folder of the suggested name exists).
        start="$(unique_path "$(start_dir "$(dirname "$path")")" "$name")"
        if printf '%s\n' "$marker" 2>/dev/null >"$start"; then
            placeholder="$start"
        else
            start="$(dirname "$start")" # read-only folder: no placeholder
        fi
    fi
    TERMFILECHOOSER_MODE=save TERMFILECHOOSER_CANCEL="$cancel_file" \
        TERMFILECHOOSER_SAVE_AS="$save_as" TERMFILECHOOSER_NAME="$name" \
        "$@" yazi --chooser-file="$out" --cwd-file="$cwd_file" "$start"
    chosen="$(chosen_path)"

    # The placeholder's current place names the file when it was renamed or
    # moved; either way it is removed (only while it still is the marker
    # file: a real file put under its old name stays), the app writes the
    # real file.
    moved=""
    if [ -n "$placeholder" ]; then
        moved="$(find_placeholder "$(dirname "$placeholder")" "$(final_dir)" "$chosen" "$(dirname "${chosen:-/}")")"
        if is_placeholder "$placeholder"; then
            rm -f "$placeholder"
        fi
        if [ -n "$moved" ] && is_placeholder "$moved"; then
            rm -f "$moved"
        fi
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
    if [ -e "$cancel_file" ]; then
        : >"$out"
    elif [ -s "$out" ]; then
        files="$(while IFS= read -r f; do [ -d "$f" ] || printf '%s\n' "$f"; done <"$out")"
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
