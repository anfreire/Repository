#!/bin/zsh

RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'

ZSHRC=~/.zshrc

RC_1='export NVM_DIR="$HOME/.nvm"'
RC_2='[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
RC_3='[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'

SILENCE='> /dev/null 2>&1'

function getNode {
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
    if ! grep -q "$RC_1" $ZSHRC; then
        echo $RC_1 >> $ZSHRC
        echo $RC_2 >> $ZSHRC
        echo $RC_3 >> $ZSHRC
    fi
    source ~/.zshrc
    nvm install node
}

function updateNPM {
    npm install -g npm@latest
}

function getTS {
    npm init -y
    npm i typescript --save-dev
    BIN_PATH="export PATH=$(pwd)/node_modules/.bin:\$PATH"
    if ! grep -q "$BIN_PATH" $ZSHRC; then
        echo $BIN_PATH >> $ZSHRC
    fi
    source ~/.zshrc
    tsc --init
}

BLA_big_dot=( 0.25 '.  ' '.. ' '...' ' ..' '  .' '   ' )
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

echo -e "${GREEN}Installing Latest NodeJS${RESET}"
BLA::start_loading_animation "${BLA_big_dot[@]}"
getNode > /dev/null 2>&1
BLA::stop_loading_animation
echo -e "${GREEN}Updating NPM${RESET}"
BLA::start_loading_animation "${BLA_big_dot[@]}"
updateNPM > /dev/null 2>&1
BLA::stop_loading_animation
echo -e "${GREEN}Installing Typescript${RESET}"
BLA::start_loading_animation "${BLA_big_dot[@]}"
getTS > /dev/null 2>&1
BLA::stop_loading_animation
zsh -c "source ~/.zshrc; exec zsh"