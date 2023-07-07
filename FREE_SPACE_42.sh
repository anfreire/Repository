#!/bin/bash

FOLDER_NAME="storage"

FLATPAK_PATH=~/.local/share/flatpak

VAR_PATH=~/.var

#---------------------------------------------------------------------------------------------------------------------------------

RED="\033[0;31m"
GREEN="\033[0;32m"
WHITE="\033[0;37m"
BOLD="\033[1m"
RESET="\033[0m"
UPDATE_FLATPAK_REP='flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo'
function sgoinfrePath() {
    link=$(readlink /sgoinfre)
    if [ $? -eq 0 ] && [ -n "$link" ] && [ -d $link ]; then
        echo $link
    else
        link=$(readlink ~/sgoinfre)
        if [ $? -eq 0 ] && [ -n "$link" ] && [ -d $link ]; then
            echo $link
        else
            echo "/sgoinfre/goinfre/Perso/$USER"
        fi
    fi
}
function read_link() {
    local path=$1
    local link=$(readlink $path)
    if [ $? -eq 0 ] && [ -n "$link" ]; then
        echo $link
    else
        echo $path
    fi
}
function printWarning() {
    local path=$1
    echo -e "${RED}${BOLD}Do not delete ${RESET}${BOLD}${path}${RESET}.\n"
    echo -e "${RED}${BOLD}Do not change the name of the folder ${RESET}${BOLD}${path}${RESET}.\n"
    echo -e "${RED}${BOLD}If you do so, all your data will be lost.${RESET}\n"
}
function replaceDir() {
    local dir_path=$1
    folderName=$(echo $dir_path | sed 's/.*\///')
    destination=$(sgoinfrePath)/$FOLDER_NAME/$folderName
    if [ ! -d $destination ]; then
        mv -f $dir_path $(sgoinfrePath)/$FOLDER_NAME/.
        ln -s $destination $dir_path
        printWarning $destination
    fi
}
function main () {
    $UPDATE_FLATPAK_REP
    path=$(sgoinfrePath)/$FOLDER_NAME
    if [ ! -d $path ]; then
        mkdir -p $path
        printWarning $path
        echo
        replaceDir $FLATPAK_PATH
        echo
        replaceDir $VAR_PATH
        echo
        echo -e "${GREEN}${BOLD}All done!${RESET}"
    else
        echo -e "${RED}${BOLD}You already have a folder named ${RESET}${BOLD}${FOLDER_NAME}${RESET}${RED}${BOLD} in your sgoinfre.${RESET}"
    fi
}
main