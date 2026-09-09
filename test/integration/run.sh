#!/usr/bin/env bash
# Integration tier: drive the mod with real keyboard and mouse input and check what it did.
#
#   test/integration/run.sh
#   ASA_INT_DISPLAY=140 test/integration/run.sh   # if :139 is taken
#
# The headless suite checks that the module sets minable_flag. This checks what the flag is
# for: that a vehicle you have driven can then be mined by hand, including a plane that has
# taken off and landed. Aircraft Realism is required for the plane half.
#
# ASA_FACTORIO         the game binary. Must be a full client: a headless build cannot
#                      render, and there is nothing to click.
# ASA_AIRCRAFTREALISM  path to an Aircraft Realism the game can load
# ASA_INT_ENV          the throwaway directory the run happens in, outside the repo
# ASA_INT_TIMEOUT      seconds to wait for the run to finish, default 600
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$root/test/integration"
# Deliberately outside the repo: the mod is symlinked in here, and an env directory inside
# the repo would make the repo contain itself.
env_dir="${ASA_INT_ENV:-$HOME/.cache/aircraft-space-age-integration}"
factorio="${ASA_FACTORIO:-$HOME/Games/Steam/steamapps/common/Factorio/bin/x64/factorio}"
ar="${ASA_AIRCRAFTREALISM:-}"
deadline="${ASA_INT_TIMEOUT:-600}"
disp="${ASA_INT_DISPLAY:-139}"

[[ -x "$factorio" ]] || { echo "no factorio binary at $factorio; set ASA_FACTORIO" >&2; exit 2; }

# Without a window manager SDL never gives the window mouse focus, so Factorio ignores
# pointer motion and clicks entirely. Keyboard still works, which makes the failure look
# like a mouse problem rather than a focus one.
wm="$(command -v xfwm4 || command -v openbox || command -v marco || true)"
[[ -n "$wm" ]] || { echo "no window manager found; mouse input will not reach the game" >&2; exit 2; }

# xvfb-run -n attaches to a display that already exists rather than failing, so a fixed
# number can silently share somebody else's session. Ask whether a server answers rather
# than whether the socket file is there: the socket outlives a server that has exited.
if [[ -e "/tmp/.X11-unix/X$disp" ]] && DISPLAY=":$disp" timeout 3 xdpyinfo >/dev/null 2>&1; then
    echo "display :$disp is in use; set ASA_INT_DISPLAY" >&2; exit 3
fi

rm -rf "$env_dir"; mkdir -p "$env_dir/mods" "$env_dir/write-data"
ln -sfn "$root" "$env_dir/mods/Aircraft-space-age"
cp -r "$here/asa-int" "$env_dir/mods/asa-int"
ar_entry=""
if [[ -n "$ar" && -d "$ar" ]]; then
    ln -sfn "$ar" "$env_dir/mods/AircraftRealism"
    ar_entry='{"name":"AircraftRealism","enabled":true},'
else
    echo "==> no Aircraft Realism given; the plane half will be skipped" >&2
fi
cat > "$env_dir/mods/mod-list.json" <<JSON
{"mods":[{"name":"base","enabled":true},{"name":"elevated-rails","enabled":true},{"name":"quality","enabled":true},{"name":"space-age","enabled":true},${ar_entry}{"name":"Aircraft-space-age","enabled":true},{"name":"asa-int","enabled":true}]}
JSON

# .../<install>/bin/x64/factorio -> .../<install>/data
install_root="$(cd "$(dirname "$factorio")/../.." && pwd)"
[[ -d "$install_root/data/core" ]] || { echo "no core data under $install_root/data" >&2; exit 2; }
printf '[path]\nread-data=%s/data\nwrite-data=%s\n[sound]\nmaster-volume=0.0\n' \
    "$install_root" "$env_dir/write-data" > "$env_dir/config.ini"

log="$env_dir/run.out"; : > "$log"
xvfb-run -n "$disp" -s "-screen 0 1280x800x24" \
    env LIBGL_ALWAYS_SOFTWARE=1 SDL_AUDIODRIVER=dummy SteamAppId=427520 ASA_WM="$wm" \
    bash -c '"$ASA_WM" >/dev/null 2>&1 & sleep 1; exec "$@"' _ \
    "$factorio" --config "$env_dir/config.ini" --mod-directory "$env_dir/mods" \
    --load-scenario asa-int/asa >> "$log" 2>&1 &
launcher=$!
trap 'pkill -f -- "--config $env_dir/config.ini" 2>/dev/null' EXIT INT TERM
export DISPLAY=":$disp"

win=""
focus() {
    win="$(xdotool search --name "Factorio" 2>/dev/null | tail -1)"
    [[ -n "$win" ]] || return 1
    xdotool windowmap "$win" 2>/dev/null
    xdotool windowraise "$win"
    # XTEST events follow the input focus, not a window id, so focus has to be set by
    # hand; and the pointer parked inside, because under PointerRoot focus the server
    # delivers to whatever is under the cursor.
    xdotool windowactivate "$win" 2>/dev/null || xdotool windowfocus "$win" 2>/dev/null
    sleep 0.4
    xdotool mousemove --window "$win" 640 400
}

selected_now() { grep -oE "ASA SEL .*" "$log" | tail -1 | sed 's/ASA SEL //'; }

# The scenario says where the target is in tiles. At zoom 1 a tile is 32 pixels and the
# camera is centred on the player, so that converts straight to a pixel. Confirm with the
# game's own selection before clicking, and nudge around if the first guess is off.
mine_target() {
    local want="$1" dx="$2" dy="$3"
    local cx cy nx ny
    cx=$(printf '%.0f' "$(echo "640 + $dx * 32" | bc -l)")
    cy=$(printf '%.0f' "$(echo "400 + $dy * 32" | bc -l)")
    for off in "0 0" "0 -16" "0 16" "-16 0" "16 0" "0 -32" "0 32"; do
        set -- $off
        nx=$(( cx + $1 )); ny=$(( cy + $2 ))
        xdotool mousemove --window "$win" "$nx" "$ny"
        sleep 0.9
        local sel; sel="$(selected_now)"
        echo "    pointer ${nx},${ny} selects: $sel"
        if [[ "$sel" == "$want" ]]; then
            echo "==> holding right mouse to mine the $want"
            xdotool mousedown 3; sleep 4; xdotool mouseup 3; sleep 1
            return 0
        fi
    done
    echo "==> never got the pointer onto the $want" >&2
    return 1
}

handled=""
end=$(( SECONDS + deadline ))
while (( SECONDS < end )); do
    marker="$(grep -oE "ASA (AWAIT-ENTER-CAR|AWAIT-ENTER-PLANE|AWAIT-EXIT|AWAIT-MINE .*|COMPLETE)" "$log" 2>/dev/null | tail -1)"
    if [[ -n "$marker" && "$marker" != "$handled" ]]; then
        handled="$marker"
        focus || { echo "no Factorio window on :$disp" >&2; break; }
        case "$marker" in
            *AWAIT-ENTER-CAR)
                echo "==> ENTER (get into the car)"; xdotool key --clearmodifiers Return; sleep 3
                echo "==> W (drive it)";              xdotool keydown w; sleep 2; xdotool keyup w; sleep 1
                echo "==> ENTER (get out)";           xdotool key --clearmodifiers Return ;;
            *AWAIT-ENTER-PLANE)
                echo "==> ENTER (get into the plane)"; xdotool key --clearmodifiers Return; sleep 2
                echo "==> W held (take off)";          xdotool keydown w; sleep 5; xdotool keyup w; sleep 1
                echo "==> S held (slow down and land)"; xdotool keydown s; sleep 12; xdotool keyup s ;;
            *AWAIT-EXIT)
                echo "==> ENTER (get out of the landed plane)"; xdotool key --clearmodifiers Return ;;
            "ASA AWAIT-MINE "*)
                read -r _ _ name dxs dys <<< "$marker"
                mine_target "$name" "${dxs#dx=}" "${dys#dy=}" ;;
            *COMPLETE) break ;;
        esac
    fi
    if grep -q "non-recoverable" "$log"; then echo "==> the game died" >&2; break; fi
    sleep 2
done

sleep 2
pkill -f -- "--config $env_dir/config.ini" 2>/dev/null
wait "$launcher" 2>/dev/null

echo
grep -oE "ASA (READY|ENTERED|EXITED|AIRBORNE-CONFIRMED|LANDED|BEFORE-MINE|MINED|AFTER-MINE|AFTER-MINE-PLANE|NO-GUNSHIP|COMPLETE).*" "$log" | awk '!s[$0]++'
if grep -q "non-recoverable" "$log"; then
    echo; echo "==> the mod raised:" >&2
    grep -A4 "non-recoverable error" "$log" | head -6 >&2
    exit 1
fi
if grep -q "ASA COMPLETE" "$log" && [[ "$(grep -c 'ASA MINED' "$log")" -ge 1 ]]; then
    echo "==> drove and mined every fixture"
else
    echo "==> the run did not finish" >&2; exit 1
fi
