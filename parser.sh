#!/bin/bash
#
# changelog
#  2021-07-24  :: Created
#
# desc :: starting with some real quick and dirty stuff here to see if this
#         is going to work at all--attempt is to make a basic, but featureful,
#         .json lexer & parser in bash.


INFILE="$1"
if [[ ! -e "$INFILE" ]] ; then
   echo "Missing input file"
   exit 1
fi


# For later, doing incremental backups on each change.
PROGDIR=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd )
BACKUP1="${PROGDIR}/.backup1.json"
BACKUP2="${PROGDIR}/.backup2.json"
BACKUP3="${PROGDIR}/.backup3.json"


declare -a TOKENS=()
declare -i GLOBAL_TOKEN_NUMBER=0

declare -Ag CURSOR=(
   [lineno]=
   [colno]=
   [pos]=
)


function Token {
   ttype="$1"
   data="$2"

   if [[ -z "$ttype" || -z "$data" ]] ; then
      echo "Missing \$ttype or \$data"
      exit 2
   fi

   declare -A "token_${GLOBAL_TOKEN_NUMBER}"=(
      # Data.
      [type]=
      [data]=

      # Meta information.
      [lineno]=${CURSOR[lineno]}
      [colno]=${CURSOR[colno]}
      [pos]=${CURSOR[pos]}
   )

   ((GLOBAL_TOKEN_NUMBER++))
}
