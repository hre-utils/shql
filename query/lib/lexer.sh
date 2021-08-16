#!/bin/bash
# lexer.sh
#
# The lexing component

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

# Using an associative array for easier querying.
declare -A KEYWORDS=(
   [write]=true
   [\print]=true
   [insert]=true
   [update]=true
   [delete]=true
)

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

#═══════════════════════════════════╡ LEXER ╞═══════════════════════════════════
function lex {
   # Fill into array, allows us to seek forwards & backwards.
   while read -rN1 c ; do
      CHARRAY+=( "$c" )
   done <<< "$INPUT_STRING"

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
         ';')  Token      'SEMI' "$CURRENT" &&  continue ;;
         ':')  Token     'COLON' "$CURRENT" &&  continue ;;
         ',')  Token     'COMMA' "$CURRENT" &&  continue ;;
         '/')  Token     'SLASH' "$CURRENT" &&  continue ;;
         '>')  Token   'GREATER' "$CURRENT" &&  continue ;;
         '(')  Token   'L_PAREN' "$CURRENT" &&  continue ;;
         ')')  Token   'R_PAREN' "$CURRENT" &&  continue ;;
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
         [[ $CURRENT == '-' && $PEEK == [[:digit:]] ]] ; then
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

   if [[ -n "${KEYWORDS[$BUFFER],,}" ]] ; then
      Token 'KEYWORD'
   else
      Token 'IDENTIFIER'
   fi
}


function number {
   BUFFER="$CURRENT"

   while [[ -n $CURRENT ]] ; do
      if [[ "$PEEK" =~ [[:digit:]] ]] ; then
         advance ; BUFFER+="$CURRENT"
      else
         break
      fi
   done

   # Create token.
   Token 'INTEGER'
}
