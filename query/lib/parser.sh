#!/bin/bash
# parser.sh
#
# The parsing component
#
# Grammar.
#     query : PERIOD [identifier PERIOD]+ method
#     

#══════════════════════════════════╡ GLOBAL ╞═══════════════════════════════════
# Kinda dumb and hacky. Starting at (-1) so the first call to advance() will
# increment by 1, thus reading the *next* character, the first.
declare -i tIDX=-1
declare -- TOKEN tNAME tPEEK1 tPEEK2
# tNAME is the tname of the current token.
# TOKEN is a nameref to the token itself.

# AST generation
declare -- AST_NODE
declare -i GLOBAL_AST_NUMBER=0

#═══════════════════════════════════╡ UTILS ╞═══════════════════════════════════
#────────────────────────────────( exceptions )─────────────────────────────────
function raise_parse_error {
   local loc="[${TOKEN[lineno]}:${TOKEN[colno]}]"
   echo -n "Parse Error: ${loc} "
   echo -e "Expected ${byl}${@}${rst}, received ${TOKEN[type]}."

   exit -2
}


function raise_key_error {
   local loc="[${TOKEN[lineno]}:${TOKEN[colno]}]"
   echo -n "Key Error: ${loc} "
   echo -e "Key ${byl}${1@Q}${rst} not found."
}


function raise_duplicate_key_error {
   local loc="[${TOKEN[lineno]}:${TOKEN[colno]}]"
   echo -n "Warning: ${loc} "
   echo -e "Key ${byl}${1@Q}${rst} already used. Overwriting previous."
}

#───────────────────────────────────( utils )───────────────────────────────────
function t_advance {
   # Advance position in file, and position in line.
   ((tIDX++)) 

   TOKEN=
   tNAME=
   tPEEK1=
   tPEEK2=

   if [[ ${tIDX} -lt ${#TOKENS[@]} ]] ; then
      tNAME=${TOKENS[tIDX]}
      declare -gn TOKEN=${tNAME}
   fi

   # Lookahead +1.
   if [[ ${tIDX} -lt $((${#TOKENS[@]}-1)) ]] ; then
      declare t1=${TOKENS[tIDX+1]}
      declare -gn tPEEK1=$t1
   fi

   # Lookahead +2.
   if [[ ${tIDX} -lt $((${#TOKENS[@]}-2)) ]] ; then
      declare t2=${TOKENS[tIDX+2]}
      declare -gn tPEEK2=$t2
   fi
}


function check_lex_errors {
   ERROR_FOUND=false

   for tname in "${TOKENS[@]}" ; do
      declare -n t="$tname"
      if [[ ${t[type]} == 'ERROR' ]] ; then
         ERROR_FOUND=true

         error_line=${FILE_BY_LINES[t[lineno]-1]}
         # Just a bunch of stupid `sed` and color escape garbage.
         color_line=$(
            sed -E "s,(.{$((t[colno]-1))})(.)(.*),\1${rd}\2${rst}\3," \
            <<< "$error_line"
         )

         msg_text="${t[data]}"
         msg_length=$(( ${#msg_text} + 2 ))

         error_pos=$(( t[colno] + 7 ))
         # Column # of the error, plus the leading "spacer" containing line
         # number, and the '|' separator.

         # Box drawing line characters that point to the offending character.
         pointer='' ; hzsep=''

         # The error is directly below the indicator, only need a pipe.
         if [[ ${msg_length} -eq ${error_pos} ]] ; then
            offset=$(( msg_length -1 ))
            pointer='│'
         # For errors that are in *front* of the initial indicator.
         elif [[ ${msg_length} -lt ${error_pos} ]] ; then
            offset=$(( msg_length -1 ))
            for i in $( seq $((error_pos - msg_length -1)) ) ; do
               hzsep+='─'
            done
            pointer="└${hzsep}┐"
         # For errors *behind* the indicator.
         elif [[ ${msg_length} -gt ${error_pos} ]] ; then
            offset=$(( error_pos -1 ))
            for i in $( seq $((msg_length - error_pos -1)) ) ; do
               hzsep+='─'
            done
            pointer="┌${hzsep}┘"
         fi

         # Print it!
         echo -e "${msg_text} ${cy}┐${rst}"
         printf "%${offset}s${cy}${pointer}${rst}\n"  ''
         printf "${cy}%4d |${rst} ${error_line}\n" ${t[lineno]-1]}
      fi
   done

   $ERROR_FOUND && exit -1
}

#═════════════════════════════════╡ AST NODES ╞═════════════════════════════════
function mkString {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_NODE_${GLOBAL_AST_NUMBER}"
   declare -g $node_name
   declare -g AST_NODE="$node_name"

   # DEBUG, print output.
   #declare -p ${node_name}
}


function mkList {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_NODE_${GLOBAL_AST_NUMBER}"
   declare -ga $node_name
   declare -g AST_NODE="$node_name"

   # DEBUG, print output.
   #declare -p ${node_name}
}


function mkDictionary {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_NODE_${GLOBAL_AST_NUMBER}"
   declare -gA $node_name
   declare -g AST_NODE="$node_name"

   # DEBUG, print output.
   #declare -p ${node_name}
}


#══════════════════════════════════╡ PARSER ╞═══════════════════════════════════
function parse {
   check_lex_errors

   grammar_data
   munch 'EOF'
}


function munch {
   t_advance
   declare -a expected=( ${1//,/ } )

   local found=false
   for exp in "${expected[@]}" ; do
      if [[ ${TOKEN[type]} == $exp ]] ; then
         found=true ; break
      fi 
   done

   $found || raise_parse_error "${expected[@]}"
}

#──────────────────────────────────( grammar )──────────────────────────────────
function grammar_data {
   munch 'STRING,L_BRACE,L_BRACKET'

   case ${TOKEN[type]} in
      'STRING')      grammar_string ;;
      'L_BRACE')     grammar_dict   ;;
      'L_BRACKET')   grammar_list   ;;
      *) raise_parse_error ;;
   esac
}


function grammar_string {
   mkString
   declare -- node_name=$AST_NODE
   declare -n s=$node_name

   s="${TOKEN[data]}"

   # Reset global AST pointer to this String node.
   AST_NODE=$node_name

   # DEBUG
   #echo "STRING(${AST_NODE} -> $s)"
}


function grammar_list {
   mkList
   declare -- node_name=$AST_NODE
   declare -n l=$node_name

   grammar_data
   l+=( ${AST_NODE} )

   while [[ ${tPEEK1[type]} == 'COMMA' ]] ; do
      munch 'COMMA'
      [[ ${tPEEK1[type]} == 'R_BRACKET' ]] && break
      grammar_data
      l+=( ${AST_NODE} )
   done
   
   munch 'R_BRACKET'

   # Reset global AST pointer to this List node.
   AST_NODE=$node_name

   # DEBUG
   #echo "$(declare -p l) -> LIST(${l[@]})"
}


function grammar_dict {
   mkDictionary
   declare -- node_name=$AST_NODE
   declare -n d=$node_name

   # Initial assignment.
   munch 'STRING' ; local key=${TOKEN[data]}
   munch 'COLON'
   grammar_data   ; d[$key]="$AST_NODE"

   while [[ ${tPEEK1[type]} == 'COMMA' ]] ; do
      munch 'COMMA'
      [[ ${tPEEK1[type]} == 'R_BRACE' ]] && break
      # Subsequent assignments.
      munch 'STRING'
      local key=${TOKEN[data]}

      if [[ -n "${d[$key]}" ]] ; then
         raise_duplicate_key_error "$key"
      fi

      munch 'COLON'
      grammar_data ; d[$key]="$AST_NODE"
   done

   munch 'R_BRACE'

   # Reset global AST pointer to this Dict node.
   AST_NODE=$node_name
}

#═══════════════════════════════════╡ CACHE ╞═══════════════════════════════════
function cache_ast {
   declare -i idx=1
   while [[ $(declare -p "_NODE_${idx}" 2>/dev/null) ]] ; do
      node_name="_NODE_${idx}"
      declare -p ${node_name}
      ((idx++))
   done > "$HASHFILE"
}