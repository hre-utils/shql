#!/bin/bash
# parser.sh
#
# The parsing component
#
# Grammar.
#     query       -> transaction (COMMA transaction)* EOF
#     transaction -> location GREATER method
#     location    -> SLASH (dict_sub|list_sub)?
#     dict_sub    -> DOT IDENTIFIER
#     list_sub    -> '[' INTEGER ']'
#     method      -> insert
#                  | update
#                  | delete
#     insert      -> insert '(' data ')'
#     update      -> update '(' data ')'
#     delete      -> '(' ')'
#     data        -> string
#                  | list
#                  | dict
#     string      -> '"' non-"-chars '"'
#     list        -> '[' data (COMMA data)* (COMMA)? ']'
#     dict        -> '{' string COLON data (COMMA string COLON data)* (COMMA)? '}'
#
#
# TRANSACTIONS = [               global list
#     transaction = {            transaction node object
#        location: [             location node list
#           loc1,                location node part
#           loc2
#        ],
#        method: 'method'        method node
#     },
#     transaction = {
#        location: [],
#        method: 'method'
#     }
# ]

#══════════════════════════════════╡ GLOBAL ╞═══════════════════════════════════
# Kinda dumb and hacky. Starting at (-1) so the first call to advance() will
# increment by 1, thus reading the *next* character, the first.
declare -i IDX=-1
declare -- TOKEN TOKEN_NAME PEEK1 PEEK2
# TOKEN_NAME is the tname of the current token.
# TOKEN is a nameref to the token itself.

#───────────────────────────────────( nodes )───────────────────────────────────
# AST generation
declare -a TRANSACTIONS
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


function raise_duplicate_key_error {
   local loc="[${TOKEN[lineno]}:${TOKEN[colno]}]"
   echo -n "Warning: ${loc} "
   echo -e "Key ${byl}${1@Q}${rst} already used. Overwriting previous."
}

#───────────────────────────────────( utils )───────────────────────────────────
function t_advance {
   # Advance position in file, and position in line.
   ((IDX++))

   TOKEN=
   TOKEN_NAME=
   PEEK1=
   PEEK2=

   if [[ ${IDX} -lt ${#TOKENS[@]} ]] ; then
      TOKEN_NAME=${TOKENS[IDX]}
      declare -gn TOKEN=${TOKEN_NAME}
   fi

   # Lookahead +1.
   if [[ ${IDX} -lt $((${#TOKENS[@]}-1)) ]] ; then
      declare t1=${TOKENS[IDX+1]}
      declare -gn PEEK1=$t1
   fi

   # Lookahead +2.
   if [[ ${IDX} -lt $((${#TOKENS[@]}-2)) ]] ; then
      declare t2=${TOKENS[IDX+2]}
      declare -gn PEEK2=$t2
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
function mkTransaction {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -gA $node_name
   declare -g AST_NODE="$node_name"

   declare -n n=$node_name
   n[location]=
   n[method]=
}


function mkLocation {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -ga $node_name
   declare -g AST_NODE="$node_name"
}


function mkMethod {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -g $node_name
   declare -g AST_NODE="$node_name"
}


function mkSubscript {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -gA $node_name
   declare -g AST_NODE="$node_name"

   declare -n n=$node_name
   n[type]=
   n[data]=
}


function mkString {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -g $node_name
   declare -g AST_NODE="$node_name"
}


function mkList {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -ga $node_name
   declare -g AST_NODE="$node_name"
}


function mkDictionary {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -gA $node_name
   declare -g AST_NODE="$node_name"
}

#══════════════════════════════════╡ PARSER ╞═══════════════════════════════════
function parse {
   check_lex_errors

   grammar_query
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
function grammar_query {
   grammar_transaction
   TRANSACTIONS+=( $AST_NODE )

   while [[ ${PEEK1[type]} == 'COMMA' ]] ; do
      munch 'COMMA'
      grammar_transaction
      TRANSACTIONS+=( $AST_NODE )
   done
}


function grammar_transaction {
   mkTransaction
   declare -- node_name=$AST_NODE
   declare -n t=$node_name

   grammar_location
   t[location]=$AST_NODE

   munch 'GREATER'
   grammar_method
   t[method]=$AST_NODE

   AST_NODE=$node_name
}


function grammar_location {
   mkLocation
   declare -- node_name=$AST_NODE
   declare -n l=$node_name

   # 1) Initial reference to root node.
   munch 'SLASH'
   grammar_sub_root
   l+=( $AST_NODE )

   ## 2) Subsequent list or dict subscription.
   #if [[ "${PEEK1[type]}" == 'L_BRACKET' ]] ; then
   #   munch 'L_BRACKET'
   #   grammar_sub_list
   #   l+=( $AST_NODE )
   #elif [[ "${PEEK1[type]}" == 'IDENTIFIER' ]] ; then
   #   grammar_sub_dict
   #   l+=( $AST_NODE )
   #fi

   # 3) Additional further subscription.
   while [[ "${PEEK1[type]}" == 'DOT' ]] ||
         [[ "${PEEK1[type]}" == 'L_BRACKET' ]] ; do
      munch 'DOT,L_BRACKET'

      if [[ "${TOKEN[type]}" == 'L_BRACKET' ]] ; then
         grammar_sub_list
         l+=( $AST_NODE )
      elif [[ "${TOKEN[type]}" == 'DOT' ]] ; then
         grammar_sub_dict
         l+=( $AST_NODE )
      fi
   done

   # NOTE: must handle in the three phases above due to the structure of the
   # query. Example:  `/foo.bar[0]`
   # The leading 'foo' is a dict subscription, but does not use the leading DOT
   # as it does in the 2nd component, '.bar'. Were we to treat the root node
   # consistently, it would look like this: `/.foo.bar[0]`. But I think that's
   # a nightmare.

   AST_NODE=$node_name
}


function grammar_sub_root {
   mkSubscript
   declare -- node_name=$AST_NODE
   declare -n d=$node_name

   d[type]=_ROOT
   d[data]=_ROOT

   AST_NODE=$node_name
}


function grammar_sub_list {
   mkSubscript
   declare -- node_name=$AST_NODE
   declare -n d=$node_name

   munch 'INTEGER'
   d[type]='list'
   d[data]=${TOKEN[data]}

   munch 'R_BRACKET'
   AST_NODE=$node_name
}


function grammar_sub_dict {
   mkSubscript
   declare -- node_name=$AST_NODE
   declare -n d=$node_name

   munch 'IDENTIFIER'
   d[type]='dict'
   d[data]="${TOKEN[data]}"

   AST_NODE=$node_name
}


function grammar_method {
   mkMethod
   declare -- node_name=$AST_NODE
   declare -n m=$node_name

   # TODO: Haven't really yet thought through how I want to make these objects
   #       per se. Still thinking about it.
   munch 'KEYWORD'
   ktype=${TOKEN[data]}

   munch 'L_PAREN'
   if [[ $ktype =~ (insert|update) ]] ; then
      grammar_data
      m[data]=$AST_NODE
   fi
   munch 'R_PAREN'

   m[type]=$ktype
   AST_NODE=$node_name
}


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
   l+=( $AST_NODE )

   while [[ ${PEEK1[type]} == 'COMMA' ]] ; do
      munch 'COMMA'
      [[ ${PEEK1[type]} == 'R_BRACKET' ]] && break
      grammar_data
      l+=( $AST_NODE )
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

   while [[ ${PEEK1[type]} == 'COMMA' ]] ; do
      munch 'COMMA'
      [[ ${PEEK1[type]} == 'R_BRACE' ]] && break
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
