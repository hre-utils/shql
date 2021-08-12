#!/bin/bash
# lexer.sh
#
# The lexing component

#══════════════════════════════════╡ GLOBAL ╞═══════════════════════════════════
declare -a TOKENS=()
declare -i GLOBAL_TOKEN_NUMBER=0 IDX=0

declare -a CHARRAY=()
declare -A CURSOR=(
   [lineno]=1
   [colno]=0
   [pos]=-1
   # Kinda dumb and hacky. Starting at (-1) so the first call to advance() will
   # increment by 1, thus reading the *next* character, the first.
)

declare -A FREEZE
declare -- CURRENT PEEK BUFFER

declare -A colormap=(
   [DOT]="$yl"
   [COLON]="$wh"
   [COMMA]="$wh"
   [STRING]="$rd"
   [NUMBER]="$bl"
   [COMMENT]="$cy"
   [L_BRACE]="$wh"
   [R_BRACE]="$wh"
   [L_BRACKET]="$wh"
   [R_BRACKET]="$wh"
   [EOF]="$gr"
)

#═══════════════════════════════════╡ UTILS ╞═══════════════════════════════════
function print_tokens {
   for tname in "${TOKENS[@]}" ; do
      declare -n t="$tname"
      declare col="${colormap[${t[type]}]}"
      printf "${col}%-10s${rst}  ${bk}%-7s${rst}  ${col}${t[data]}${rst}\n" \
         ${t[type]} \
         "${t[lineno]}:${t[colno]}"
   done
}


function Token {
   ttype="$1"
   data="${2:-$BUFFER}"

   if [[ -z "$ttype" ]] ; then
      echo "Missing \$ttype" ; exit 2
   fi

   # Make token. Add to list.
   tname="token_${GLOBAL_TOKEN_NUMBER}"
   TOKENS+=( $tname )

   declare -Ag $tname
   declare -n t=$tname

   # Data.
   t[type]="$ttype"
   t[data]="$data"

   # Meta information.
   t[lineno]=${FREEZE[lineno]}
   t[colno]=${FREEZE[colno]}
   t[pos]=${FREEZE[pos]}

   # Increment.
   ((GLOBAL_TOKEN_NUMBER++))

   # TODO: Hitting an odd situation in which the first increment is returning a
   #       '1' status for some reason. Need to figure out why that is. Remove
   #       elements to narrow down. I don't think incrementing a number should
   #       return anything but '0'.
   return 0
}

#════════════════════════════════════╡ GO ╞═════════════════════════════════════
function lex {
   # Fill into array, allows us to seek forwards & backwards.
   while read -rN1 c ; do
      CHARRAY+=( "$c" )
   done < "$INFILE"

   # TODO;XXX
   # Creating secondary line buffer to do better debug output printing.
   mapfile -td $'\n' FILE_BY_LINES < "$INFILE"

   # Iterate over array of characters. Lex into tokens.
   while [[ ${CURSOR[pos]} -lt ${#CHARRAY[@]} ]] ; do
      advance
      [[ -z $CURRENT ]] && break

      # "Freeze" the line number and cursor number, such that they're attached
      # to the *start* of a token, rather than the end.
      FREEZE[lineno]=${CURSOR[lineno]}
      FREEZE[colno]=${CURSOR[colno]}
      FREEZE[pos]=${CURSOR[pos]}

      # Skip comments.
      if [[ "$CURRENT" == '#' ]] ; then
         comment ; continue
      fi

      # Skip whitespace.
      [[ "$CURRENT" =~ [[:space:]] ]] && continue

      # Symbols.
      case "$CURRENT" in
         '.')  Token       'DOT' "$CURRENT" &&  continue ;;
         ':')  Token     'COLON' "$CURRENT" &&  continue ;;
         ',')  Token     'COMMA' "$CURRENT" &&  continue ;;
         '{')  Token   'L_BRACE' "$CURRENT" &&  continue ;;
         '}')  Token   'R_BRACE' "$CURRENT" &&  continue ;;
         '[')  Token 'L_BRACKET' "$CURRENT" &&  continue ;;
         ']')  Token 'R_BRACKET' "$CURRENT" &&  continue ;;
      esac

      # Strings.
      if [[ "$CURRENT" =~ [\"\'] ]] ; then
         string "$CURRENT" ; continue
      fi

      # Identifiers.
      if [[ "$CURRENT" =~ [[:alpha:]_] ]] ; then
         identifier ; continue
      fi

      # Numbers.
      if [[ $CURRENT =~ [[:digit:]] ]] ||
         [[ "$CURRENT" == '-' && "$PEEK" =~ [1-9] ]] ; then
         number ; continue
      fi

      # If none of the above, it's an invalid character.
      local loc="[${FREEZE[lineno]}:${FREEZE[colno]}]"
      Token 'ERROR'  "Syntax Error: $loc Invalid character ${CURRENT@Q}."
   done

   Token 'EOF' 'null'
}


function advance {
   # Advance position in file, and position in line.
   ((CURSOR[pos]++))
   ((CURSOR[colno]++))

   CURRENT=
   PEEK=

   if [[ ${CURSOR[pos]} -lt ${#CHARRAY[@]} ]] ; then
      CURRENT=${CHARRAY[CURSOR[pos]]}
   fi

   if [[ ${CURSOR[pos]} -lt $((${#CHARRAY[@]}-1)) ]] ; then
      PEEK=${CHARRAY[CURSOR[pos]+1]}
   fi

   if [[ "$CURRENT" == $'\n' ]] ; then
      ((CURSOR[lineno]++))    # Increment line number.
      CURSOR[colno]=0         # Reset column position.
   fi
}


function comment {
   while [[ -n $CURRENT ]] ; do
      [[ "$PEEK" =~ [$'\n'] ]] && break
      advance
   done
}


function string {
   delim="$1"
   declare -a buffer=()

   while [[ -n $CURRENT ]] ; do
      if [[ "$PEEK" =~ [$delim] ]] ; then
         if [[ "${buffer[-1]}" == '\\' ]] ; then
            unset buffer[-1]
         else
            break
         fi
      fi
      advance
      buffer+=( "$CURRENT" )
   done

   # Set global buffer to joined output of local buffer.
   # >>> BUFFER = ''.join(local_buffer)
   BUFFER=''
   for c in "${buffer[@]}" ; do
      BUFFER+="$c"
   done

   # Create token.
   Token 'STRING'

   # Skip final closing ('|").
   advance
}


function identifier {
   BUFFER="$CURRENT"

   while [[ -n $CURRENT ]] ; do
      [[ "${PEEK}" =~ [^[:alnum:]_] ]] && break
      advance ; BUFFER+="$CURRENT"
   done

   #Token 'IDENTIFIER'
   local loc="[${FREEZE[lineno]}:${FREEZE[colno]}]"
   Token 'ERROR'  "Syntax Error: $loc 'Identifier' not yet implemented."
}


function number {
   BUFFER="$CURRENT"

   local decimal=false
   while [[ -n $CURRENT ]] ; do
      if [[ "$PEEK" == '.' ]] ; then
         # If we already have had a decimal point, break.
         $decimal && break

         # Else, append decimal to the number and continue.
         decimal=true
         advance ; BUFFER+="$CURRENT"
      elif [[ "$PEEK" =~ [[:digit:]] ]] ; then
         advance ; BUFFER+="$CURRENT"
      else
         break
      fi
   done

   # Create token.
   Token 'NUMBER'
}
