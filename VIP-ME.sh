#!/bin/bash

GREEN_BOLD='\033[1;32m'
RED_BOLD='\033[1;31m'
WHITE_BOLD='\033[1;37m'
RESET='\033[0m'
PWD=$(pwd)
FOLDER_SUFX_1="42-EXAM"
FOLDER_SUFX_2=".system"
FILE_SUFX="main.cpp"
TO_RM_1='if ((input == "remove_grade_time" || input == "new_ex" || input == "force_success") && !setting_dcc)'
TO_RM_2='std::cout << " ❌ Cheat commands are currently disabled, use " << LIME << BOLD << "settings" << RESET << " command." << std::endl;'
TO_RPL='else if (input == "finish" || input == "exit" || input == "quit")'
TO_ADD='if (input == "finish" || input == "exit" || input == "quit")'

function remove_from_main() {
    sed -i "s/$1//g" $MAIN_FILE
}

function replace_in_main() {
    sed -i "s/$1/$2/g" $MAIN_FILE
}

function remove_suffix() {
    local path=$1
    local suffix=$2
    if [[ $path == *"$suffix" ]]; then
        path="${path::-${#suffix}}"
    fi
    echo $path
}

function adjust_path() {
    local path=$1
    if [[ $path == "." ]]; then
        path="$PWD"
    else if [[ $path == ".." ]]; then
        path=$(dirname "$PWD")
    else if [[ $path == "~" ]]; then
        path="$HOME"
    else if [[ $path == "~/"* ]]; then
        path="$HOME/${path:2}"
    else if [[ $path == "/"* ]]; then
        path="$path"
    else
        path="$PWD/$path"
    fi
    fi
    fi
    fi
    fi
    echo $path
}

echo -e -n "Enter the path of 42-EXAM directory: "
read path

path=$(remove_suffix $path "/")

path=$(adjust_path $path)

ERROR=""

if [ -d "$path" ]; then
    EXAM_PATH="$path"
else
    ERROR="${RED_BOLD}No such directory${RESET}"
fi

if [ -z "$ERROR"] && [ -d "$EXAM_PATH/$FOLDER_SUFX_1" ]; then
    EXAM_PATH="$EXAM_PATH/$FOLDER_SUFX_1"
fi

if [ -z "$ERROR"] && [ -d "$EXAM_PATH/$FOLDER_SUFX_2" ]; then
    EXAM_PATH="$EXAM_PATH/$FOLDER_SUFX_2"
else
    ERROR="${RED_BOLD}This directory is not the 42-EXAM directory${RESET}: ${WHITE_BOLD}$EXAM_PATH${RESET}"
fi

if [ -z "$ERROR" ] && [ -f "$EXAM_PATH/$FILE_SUFX" ]; then
    MAIN_FILE="$EXAM_PATH/$FILE_SUFX"
else
    ERROR="${RED_BOLD}Can't find the main file${RESET}: ${WHITE_BOLD}$EXAM_PATH/$FILE_SUFX${RESET}"
fi

if [ ! -z "$ERROR" ]; then
    echo -e "$ERROR"
    echo -n "Do you want to clone the repo? (y/n): "
    read answer
    if [ "$answer" == "y" ]; then
        git clone https://github.com/JCluzet/42_EXAM 42-EXAM-MOD
        MAIN_FILE="$PWD/42-EXAM-MOD/$FOLDER_SUFX_2/$FILE_SUFX"
        EXAM_PATH="$PWD/42-EXAM-MOD/$FOLDER_SUFX_2"
    else
        exit 1
    fi
fi

remove_from_main "$TO_RM_1"
remove_from_main "$TO_RM_2"
replace_in_main "$TO_RPL" "$TO_ADD"

if grep -q "$TO_RM_1" "$MAIN_FILE" || grep -q "$TO_RM_2" "$MAIN_FILE" || ! grep -q "$TO_ADD" "$MAIN_FILE"; then
    echo -e "${RED_BOLD}Something went wrong${RESET}"
    exit 1
fi

echo -e "${GREEN_BOLD}Done${RESET}: ${WHITE_BOLD}$EXAM_PATH/$FILE_SUFX${RESET} was updated"

EXAM_PATH=$(remove_suffix $EXAM_PATH "/$FOLDER_SUFX_2")
echo -e "${GREEN_BOLD}To compile the program, use the command: ${WHITE_BOLD}cd $EXAM_PATH; make${RESET}"