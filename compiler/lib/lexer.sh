#!/bin/bash
# The lexing component
#
# Methods:
#  1. lex
#  2. print_tokens

#══════════════════════════════════╡ GLOBAL ╞═══════════════════════════════════
declare -a TOKENS=()
declare -i GLOBAL_TOKEN_NUMBER=0 IDX=0

declare -a CHARRAY=()
declare -A CURSOR=(
   [lineno]=1
   [colno]=0
   [pos]=-1
)

declare -A FREEZE
# At the beginning of each loop, the cursor information is "frozen", allowing
# us to retain the start position of multi-character tokens (keywords, strings,
# etc.).

declare -- CURRENT PEEK BUFFER
# Global pointer to subsequent tokens, and string buffer to hold the contents
# of multi-character tokens.

declare -A colormap=(
   [DOT]="$yl"
   [FLOAT]="$bl"
   [COLON]="$wh"
   [COMMA]="$wh"
   [STRING]="$rd"
   [INTEGER]="$bl"
   [COMMENT]="$cy"
   [L_BRACE]="$wh"
   [R_BRACE]="$wh"
   [L_BRACKET]="$wh"
   [R_BRACKET]="$wh"
   [EOF]="$gr"
)

#═══════════════════════════════════╡ UTILS ╞═══════════════════════════════════
function print_tokens {
   # For debugging. Prints a pretty-printed format of the token list. Currently
   # unsuitable for dumping to a text file, as it won't render the color
   # esacpes. Working on creating a --no-color flag for this purpose.
   for tname in "${TOKENS[@]}" ; do
      declare -n t="$tname"
      declare col="${colormap[${t[type]}]}"
      printf "${col}%-10s${rst}  ${bk}%-7s${rst}  ${col}${t[data]}${rst}\n" \
         ${t[type]} \
         "${t[lineno]}:${t[colno]}"
   done
}


function Token {
   # This is a "Class"... kinda. Realistically this is not how I would create
   # an actual class in Bash, however it suits the current application.
   #
   # Parameters:
   #     $1  string, token type
   #     $2  string (opt), payload of the token, or contents of buffer if unset
   #
   # Does:
   #     1. Globally declares an associative array, with incrementing name
   #     2. Appends array name to global TOKENS list
   #     3. Assigns type/data information from above
   #     4. Assigns cursor information for debugging from FREEZE (see global
   #        section for information)
   #     5. Incremenents global token name counter

   ttype="$1"
   data="${2:-$BUFFER}"

   if [[ -z "$ttype" ]] ; then
      echo "Missing \$ttype" ; exit 2
   fi

   # Generate unique token name, add to global list.
   tname="token_${GLOBAL_TOKEN_NUMBER}"
   TOKENS+=( $tname )

   # Create token, and local nameref.
   declare -Ag $tname
   declare -n t=$tname

   # Assign data.
   t[type]="$ttype"
   t[data]="$data"

   # Assign meta information.
   t[lineno]=${FREEZE[lineno]}
   t[colno]=${FREEZE[colno]}
   t[pos]=${FREEZE[pos]}

   ((++GLOBAL_TOKEN_NUMBER))
   # If an ((expression)) evaluates to 0, it returns a '1' exit status. To
   # ensure we always have a '0' status, ((++var)) will increment first, then
   # return.
}

#════════════════════════════════════╡ GO ╞═════════════════════════════════════
function lex {
   # Fill individual characters into array, allows more easy 'peek' operations.
   while read -rN1 c ; do
      CHARRAY+=( "$c" )
   done < "$INFILE"

   # Creating secondary line buffer to do better debug output printing. It would
   # be more efficient to *only* hold a buffer of lines up until each newline.
   # Unpon an error, we'd only need to save the singular line, then can resume
   # overwriting. This is in TODO already.
   mapfile -td $'\n' FILE_BY_LINES < "$INFILE"

   while [[ ${CURSOR[pos]} -lt ${#CHARRAY[@]} ]] ; do
      advance
      [[ -z $CURRENT ]] && break

      # See detail in the 'GLOBAL' section concerning FREEZE.
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

   CURRENT= PEEK=

   if [[ ${CURSOR[pos]} -lt ${#CHARRAY[@]} ]] ; then
      CURRENT=${CHARRAY[CURSOR[pos]]}
   fi

   if [[ ${CURSOR[pos]} -lt $((${#CHARRAY[@]}-1)) ]] ; then
      PEEK=${CHARRAY[CURSOR[pos]+1]}
   fi

   # If we hit a newline...
   if [[ "$CURRENT" == $'\n' ]] ; then
      ((CURSOR[lineno]++))    # Increment line number.
      CURSOR[colno]=0         # Reset column position.
   fi
}


function comment {
   # There are no multiline comments. Seeks from '#' to the end of the line.
   # There are no EOL tokens. Looks for '\n'.
   while [[ -n $CURRENT ]] ; do
      [[ "$PEEK" =~ [$'\n'] ]] && break
      advance
   done
}


function string {
   # Supports both '/" characters to indicate strings, and intermediate '/"
   # characters can be escaped with a backslash.
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
   # NYI. Identifiers currently raise a syntax error. However they will be
   # supported in future versions. They follow the same naming conventions as
   # shell words.
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
   # All "numbers" are floats. There are no supported sci, hex, or binary
   # representations.
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

   if $decimal ; then
      Token 'FLOAT'
   else
      Token 'INTEGER'
   fi
}
