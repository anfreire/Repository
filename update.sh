#!/bin/bash

OK="\033[1;32mOK\033[0m:"
FAIL="\033[1;31mFAILED\033[0m:"
WARN="\033[1;33mWARNING\033[0m:"
BOLD_WHITE="\033[1;37m"
RESET="\033[0m"
BLA_passing_dots=( 0.25 '.  ' '.. ' '...' ' ..' '  .' '   ' )
declare -a BLA_active_loading_animation
BLA::play_loading_animation_loop() {
  while true ; do
    for frame in "${BLA_active_loading_animation[@]}" ; do
      printf "\r%s" "${frame}"
      sleep "${BLA_loading_animation_frame_interval}"
    done
  done
}
BLA::start_loading_animation() {
  BLA_active_loading_animation=( "${@}" )
  BLA_loading_animation_frame_interval="${BLA_active_loading_animation[0]}"
  unset "BLA_active_loading_animation[0]"
  tput civis
  BLA::play_loading_animation_loop &
  BLA_loading_animation_pid="${!}"
}
BLA::stop_loading_animation() {
  kill "${BLA_loading_animation_pid}" &> /dev/null
  printf "\n"
  tput cnorm
}

# BLA::start_loading_animation "${BLA_passing_dots[@]}"
# ...
# BLA::stop_loading_animation

function check_file_changed() {
    local name=$1
    local file=$2
    local commands=("${@:3}")
    date_before=$(date -r $file +%s)
    BLA::start_loading_animation "${BLA_passing_dots[@]}"
    for command in "${commands[@]}"; do
        $command > /dev/null 2>&1
    done
    BLA::stop_loading_animation
    date_after=$(date -r $file +%s)
    if [ $date_before -ne $date_after ]; then
        echo -e "$OK $BOLD_WHITE$name$RESET updated successfully"
    else
        echo -e "$FAIL $BOLD_WHITE$name$RESET not updated"
    fi
}

check_file_changed "Spotify_Linux" "Spotify_Linux.sh" "curl -o Spotify_Linux.sh https://raw.githubusercontent.com/SpotX-CLI/SpotX-Linux/main/install.sh" "chmod +x Spotify_Linux.sh"
check_file_changed "Spotify_Mac" "Spotify_Mac.sh" "curl -o Spotify_Mac.sh https://raw.githubusercontent.com/SpotX-CLI/SpotX-Mac/main/install.sh" "chmod +x Spotify_Mac.sh"
check_file_changed "Spotify_Windows" "Spotify_Windows.bat" "curl -o Spotify_Windows.bat https://raw.githubusercontent.com/mrpond/BlockTheSpot/master/BlockTheSpot.bat"
