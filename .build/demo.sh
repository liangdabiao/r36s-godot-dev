#!/bin/bash
# PORTMASTER: demo.zip, demo.sh

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# Localização do PortMaster
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
source $controlfolder/device_info.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

GAMEDIR="/roms/ports/demo"
CONFDIR="$GAMEDIR/conf"

mkdir -p "$CONFDIR"

export XDG_CONFIG_HOME="$CONFDIR"
export XDG_DATA_HOME="$CONFDIR"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

runtime="frt_3.5.2"

if [ ! -f "$controlfolder/libs/${runtime}.squashfs" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    echo "Runtime do Godot não encontrado. Atualize o PortMaster ou baixe o runtime manualmente." > /dev/tty0
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${runtime}.squashfs"
fi

godot_dir="$HOME/godot"
godot_file="$controlfolder/libs/${runtime}.squashfs"
$ESUDO mkdir -p "$godot_dir"
$ESUDO umount "$godot_file" || true
$ESUDO mount "$godot_file" "$godot_dir"
PATH="$godot_dir:$PATH"

export FRT_NO_EXIT_SHORTCUTS=1
export FRT_EXIT_SHORTCUT=esc
GODOT_OPTS="${GODOT_OPTS:-} --video-driver GLES2"

$ESUDO chmod 666 /dev/uinput
$GPTOKEYB "$runtime" -c "./demo.gptk" &
"$runtime" $GODOT_OPTS --main-pack "demo.pck"

$ESUDO umount "$godot_dir"
$ESUDO kill -9 $(pidof gptokeyb)
$ESUDO systemctl restart oga_events &
printf "\033c" > /dev/tty0
