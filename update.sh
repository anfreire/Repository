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

function execute_commands() {
    local commands=("${@}")
    for command in "${commands[@]}"; do
        $command > /dev/null 2>&1
    done
}

check_file_changed "Spotify_Linux" "Spotify/Linux/Spotify_Linux.sh" "curl -o Spotify/Linux/Spotify_Linux.sh https://raw.githubusercontent.com/SpotX-CLI/SpotX-Linux/main/install.sh" "chmod +x Spotify/Linux/Spotify_Linux.sh"
check_file_changed "Spotify_Mac" "Spotify/macOS/Spotify_Mac.sh" "curl -o Spotify/macOS/Spotify_Mac.sh https://raw.githubusercontent.com/SpotX-CLI/SpotX-Mac/main/install.sh" "chmod +x Spotify/macOS/Spotify_Mac.sh"
check_file_changed "Spotify_Windows" "Spotify/Windows/Spotify_Windows.bat" "curl -o Spotify/Windows/Spotify_Windows.bat https://raw.githubusercontent.com/mrpond/BlockTheSpot/master/BlockTheSpot.bat"
check_file_changed "Windows_Tools" "Windows/Windows_Tools.bat" "curl -o Windows/Windows_Tools.bat https://raw.githubusercontent.com/massgravel/Microsoft-Activation-Scripts/master/MAS/All-In-One-Version/MAS_AIO.cmd"
check_file_changed "Office - 32bit" "Office/32bit/Office_32.zip" \
"curl -o Office/32bit/bin.exe https://github.com/aesticode/microsoft-office-2021/raw/main/Office2021/bin.exe" \
"curl -o Office/32bit/Install_Essential.bat https://raw.githubusercontent.com/aesticode/microsoft-office-2021/main/Office2021/Install-x32-basic.bat" \
"curl -o Office/32bit/Install_Bloated.bat https://github.com/aesticode/microsoft-office-2021/blob/main/Office2021/Install-x32.bat" \
"curl -o Office/32bit/Activator.bat https://raw.githubusercontent.com/aesticode/microsoft-office-2021/main/Office2021/Activator.bat" \
"curl -o Office/32bit/configuration/configuration-x32-basic.xml https://github.com/aesticode/microsoft-office-2021/blob/main/Office2021/configuration/configuration-x32-basic.xml" \
"curl -o Office/32bit/configuration/configuration-x32.xml https://raw.githubusercontent.com/aesticode/microsoft-office-2021/main/Office2021/configuration/configuration-x32.xml" \
execute_commands "cd Office/32bit" "zip -r Office_32.zip ./* -x Office_32.zip"  "cd ../.."
check_file_changed "Office - 64bit" "Office/64bit/Office_64.zip" \
"curl -o Office/64bit/bin.exe https://github.com/aesticode/microsoft-office-2021/raw/main/Office2021/bin.exe" \
"curl -o Office/64bit/Install_Essential.bat https://raw.githubusercontent.com/aesticode/microsoft-office-2021/main/Office2021/Install-x64-basic.bat" \
"curl -o Office/64bit/Install_Bloated.bat https://github.com/aesticode/microsoft-office-2021/blob/main/Office2021/Install-x64.bat" \
"curl -o Office/64bit/Activator.bat https://raw.githubusercontent.com/aesticode/microsoft-office-2021/main/Office2021/Activator.bat" \
"curl -o Office/64bit/configuration/configuration-x64-basic.xml https://github.com/aesticode/microsoft-office-2021/blob/main/Office2021/configuration/configuration-x64-basic.xml" \
"curl -o Office/64bit/configuration/configuration-x64.xml https://raw.githubusercontent.com/aesticode/microsoft-office-2021/main/Office2021/configuration/configuration-x64.xml" \
execute_commands "cd Office/64bit" "zip -r Office_64.zip ./* -x Office_64.zip"  "cd ../.."
