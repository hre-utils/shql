#!/bin/bash
# changelog
#  2021-07-24  :: Created
#
# desc :: starting with some real quick and dirty stuff here to see if this
#         is going to work at all--attempt is to make a basic, but featureful,
#         .json lexer & parser in bash. It shall be .shon. Shell object
#         notation.
# todo :: 1) Change all CURRENT's to be the namerefs themselves, and give all
#            dicts a [name] prop to refer to themselves. Better than needing to
#            use a `declare -p`.
#         2) Could probably declare a LINE_BUFFER[], which holds the contents of
#            each line up to a $'\n', at which point it's cleared. Allow us to
#            not need to hold the entire contents of the file in yet another
#            array. Upon hitting an ERROR token, the message, along with the
#            original line, are saved to props in the object.

#══════════════════════════════════╡ GLOBAL ╞═══════════════════════════════════
# Color garbage.
rst=$(tput sgr0)                                   # Reset
bk="$(tput setaf 0)"                               # Black
rd="$(tput setaf 1)"  ;  brd="$(tput bold)${rd}"   # Red     ;  Bright Red
gr="$(tput setaf 2)"  ;  bgr="$(tput bold)${gr}"   # Green   ;  Bright Green
yl="$(tput setaf 3)"  ;  byl="$(tput bold)${yl}"   # Yellow  ;  Bright Yellow
bl="$(tput setaf 4)"  ;  bbl="$(tput bold)${bl}"   # Blue    ;  Bright Blue
mg="$(tput setaf 5)"  ;  bmg="$(tput bold)${mg}"   # Magenta ;  Bright Magenta
cy="$(tput setaf 6)"  ;  bcy="$(tput bold)${cy}"   # Cyan    ;  Bright Cyan
wh="$(tput setaf 7)"  ;  bwh="$(tput bold)${wh}"   # White   ;  Bright White

INFILE="$1"
if [[ ! -e "$INFILE" ]] ; then
   echo "Missing input file"
   exit 1
fi

# For printing better error output.
declare -a FILE_BY_LINES

# For later, doing incremental backups on each database change.
PROGDIR=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd )
#BACKUP1="${PROGDIR}/.backup1.json"
#BACKUP2="${PROGDIR}/.backup2.json"
#BACKUP3="${PROGDIR}/.backup3.json"

# Hash for caching.
RUN_HASH=$( md5sum "$INFILE" )
RUN_HASH=${RUN_HASH%% *}
HASHFILE="${PROGDIR}/cache/${RUN_HASH}"
mkdir -p "$(dirname "${HASHFILE}")"

for f in "${PROGDIR}"/lib/* ; do
   source "$f"
done

source "${PROGDIR}/ents/pretty_printer.sh"
source "${PROGDIR}/config.sh"

# Cached?
[[ -e "$HASHFILE" ]] && exit 0

# Compile.
lex
parse
cache_ast

#pretty_print
