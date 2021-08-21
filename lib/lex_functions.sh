#───────────────────────────────────( utils )───────────────────────────────────
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
      echo "Missing \$ttype" 1>&2 ; exit 2
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

#──────────────────────────────────( tokens )───────────────────────────────────
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
