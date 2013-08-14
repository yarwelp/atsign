#!/bin/bash

ATSIGN_CACHE="$HOME/.cache/atsign"

atsign_index()
{
    local LANG="C.UTF-8"
    local LC_ALL="C.UTF-8"
    local LC_CTYPE="C.UTF-8"
    local LC_COLLATE="C.UTF-8"

    awk '
    {
        split($1, packages, ":")
        package = packages[1]

        for (i = 2; i <= NF; ++i)
        {
            last = split($i, path, "/")
            file = path[last]

            if (index(dict[file], package))
                continue

            dict[file] = (dict[file] " " package)
        }
    }

    END {
        for (x in dict)
            print x ":" dict[x]
    }
    ' | sort
}

atsign_cache()
{
    echo "Indexing $1 files..." 1>&2

    apt-file --regexp search "$2" | atsign_index > "$ATSIGN_CACHE/$1"
}

atsign_update()
{
    mkdir -p "$ATSIGN_CACHE"

    apt-file update 1>&2

    atsign_cache all '.'
    atsign_cache bin '(^|.*/)(s?bin|games|lib)/[^/\s]+$'
    atsign_cache lib '/lib[^/\s]+\.(a|so)[^/\s]*$'
}

atsign_search()
{
    local DICT="$ATSIGN_CACHE/$1"

    test -d "$ATSIGN_CACHE" || atsign_update

    case "$1" in
        all)
            local PATTERN=".*$2.*"
            ;;
        bin)
            local PATTERN="$2"
            ;;
        lib)
            local PATTERN="$2\.(a|so)"
            ;;
        *)
            echo "what?" 1>&2
            return 1
    esac

    look -b "$2" "$DICT" | grep -P "^$PATTERN: " | atsign_index | column -t
}

atsign()
{
    if [ $? = 127 ]
    then
        local DICT=bin
        local FILE=$(history 2 | head -n 1 | tr -s \  \ | cut -f3 -d\  | tr -d '[:space:]')
    elif [ x"" != x"$1" ]
    then
        case "$1" in
            -u)
                atsign_update
                return
                ;;
            -l*)
                local DICT=lib
                local FILE="lib$(echo "$1" | sed 's/^-l//')"
                ;;
            *)
                local DICT=all
                local FILE="$1"
        esac
    else
        echo no 1>&2
        return 1
    fi

    local BUFFER=$(mktemp)

    (
    atsign_search "$DICT" "$FILE" > "$BUFFER" || return 1

    local COUNT=$(wc -l "$BUFFER" | cut -d' ' -f1)

    case $COUNT in
        0)
            echo "$FILE: no match" 1>&2
            exit 1
            ;;
        1)
            cat "$BUFFER"
            local CHOICE=1
            ;;
        *)
            nl "$BUFFER"
            echo -n "> "
            local CHOICE=$(head -1)
            expr \( "$CHOICE" '>' 0 \) \& \( "$CHOICE" '<=' $COUNT \) >/dev/null || exit 1
            ;;
    esac

    local PACKAGE=$(sed "$CHOICE!D" "$BUFFER" | cut -d: -f1)

    /usr/bin/sudo /usr/bin/aptitude --prompt install "$PACKAGE"
    )

    rm -f "$BUFFER"
}

alias @=atsign
