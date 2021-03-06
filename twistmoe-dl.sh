#!/usr/bin/env bash
#
# Download anime from twist.moe using CLI
#
#/ Usage:
#/   ./twistmoe-dl.sh [-s <anime_slug>] [-e <episode_num1,num2...>]
#/
#/ Options:
#/   -s <slug>          Anime slug, can be found in $_ANIME_LIST_FILE
#/   -e <num1,num2...>  Optional, episode number to download
#/                      multiple episode numbers seperated by ","
#/   -h | --help        Display this help message

set -e
set -u

usage() {
    printf "%b\n" "$(grep '^#/' "$0" | cut -c4-)" && exit 1
}

set_var() {
    _SCRIPT_PATH=$(dirname "$0")
    _CURL=$(command -v curl)
    _JQ=$(command -v jq)
    _FZF=$(command -v fzf)
    _DECRYPT_SCRIPT="$_SCRIPT_PATH/bin/decrypt.py"

    _HOST="https://twist.moe"
    _API_URL="$_HOST/api/anime"
    _ACCESS_TOKEN="1rj2vRtegS8Y60B3w3qNZm5T2Q0TN2NR"

    _ANIME_LIST_FILE="$_SCRIPT_PATH/anime.list"
    _SOURCE_FILE=".source.json"
}

set_args() {
    expr "$*" : ".*--help" > /dev/null && usage
    while getopts ":hs:e:" opt; do
        case $opt in
            s)
                _ANIME_SLUG="$OPTARG"
                ;;
            e)
                _ANIME_EPISODE="$OPTARG"
                ;;
            h)
                usage
                ;;
            \?)
                echo "[ERROR] Invalid option: -$OPTARG" >&2
                usage
                ;;
        esac
    done
}

download_anime_list() {
    $_CURL -sS "$_API_URL" -H "x-access-token: $_ACCESS_TOKEN" \
        | $_JQ -r '.[] | "[\(.slug.slug)] \(.title)\(if .alt_title != null then " (\(.alt_title))" else "" end)"' > "$_ANIME_LIST_FILE"
}

download_source() {
    mkdir -p "$_SCRIPT_PATH/$_ANIME_SLUG"
    $_CURL -sS "$_API_URL/$_ANIME_SLUG/sources" -H "x-access-token: $_ACCESS_TOKEN" > "$_SCRIPT_PATH/$_ANIME_SLUG/$_SOURCE_FILE"
}

get_episode_link() {
    # $1: episode number
    local s
    s=$($_JQ -r '.[] | select(.number==($num | tonumber)) | .source' --arg num "$1" < "$_SCRIPT_PATH/$_ANIME_SLUG/$_SOURCE_FILE")
    if [[ "$s" == "" ]]; then
        echo "[ERROR] Episode not found!" >&2 && exit 1
    else
        decrypt_source "$s"
    fi
}

download_episodes() {
    # $1: episode number string
    if [[ "$1" == *","* ]]; then
        IFS=","
        read -ra ADDR <<< "$1"
        for e in "${ADDR[@]}"; do
            download_episode "$e"
        done
    else
        download_episode "$1"
    fi
}

download_episode() {
    # $1: episode number
    local l
    l=$(get_episode_link "$1")
    if [[ "$l" != *"/"* ]]; then
        echo "[ERROR] Wrong download link or episode not found!" >&2 && exit 1
    fi

    echo "[INFO] Downloading Episode $1..."
    $_CURL -L -g -o "$_SCRIPT_PATH/$_ANIME_SLUG/${_ANIME_SLUG}-${1}.mp4" "$_HOST/$l" \
        -H "user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.157 Safari/537.36'" \
        -H "Referer: $_HOST"
}

decrypt_source() {
    # $1: encrypted str
    $_DECRYPT_SCRIPT -s "$1" | tail -1
}

select_episodes_to_download() {
    $_JQ -r '.[] | "[\(.number)] E\(.number) \(.updated_at)"' < "$_SCRIPT_PATH/$_ANIME_SLUG/$_SOURCE_FILE" >&2
    echo -n "Which episode(s) to downolad: " >&2
    read -r s
    echo "$s"
}

main() {
    set_args "$@"
    set_var

    if [[ -z "${_ANIME_SLUG:-}" ]]; then
        download_anime_list
        if [[ ! -f "$_ANIME_LIST_FILE" ]]; then
            echo "[ERROR] $_ANIME_LIST_FILE not found!" && exit 1
        fi
        _ANIME_SLUG=$($_FZF < "$_ANIME_LIST_FILE" | awk -F']' '{print $1}' | sed -E 's/^\[//')

        if [[ "$_ANIME_SLUG" == "" ]]; then
            exit 0
        fi
    fi

    download_source

    if [[ -z "${_ANIME_EPISODE:-}" ]]; then
        _ANIME_EPISODE=$(select_episodes_to_download)
    fi
    download_episodes "$_ANIME_EPISODE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
