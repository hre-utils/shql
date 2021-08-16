#!/bin/bash
# The parsing component
#
# Grammar.
#  request     -> transaction (SEMI transaction)* EOF
#  transaction -> query GREATER method
#  query       -> SLASH (index)?
#  index       -> dict_index
#               | list_index
#  dict_index  -> DOT IDENTIFIER
#  list_index  -> '[' INTEGER ']'
#  method      -> insert
#               | update
#               | delete
#               | print
#               | write
#  insert      -> insert '(' [IDENTIFIER COMMA] data ')'
#  update      -> update '(' data ')'
#  delete      -> '(' ')'
#  print       -> '(' ')'
#  write       -> '(' string ')'
#  data        -> string
#               | list
#               | dict
#  string      -> '"' non-"-chars '"'
#  list        -> '[' data (COMMA data)* (COMMA)? ']'
#  dict        -> '{' string COLON data (COMMA string COLON data)* (COMMA)? '}'
#
#
# Example created data structure.
#  declare -a REQUEST=(
#     R1
#     R2
#  )
#
#  declare -A R1=(
#     [query]=Q1
#     [method]=M1
#  )
#
#  declare -A Q1=(
#     [type]=list|dict
#     [data]=
#  )
#
#  declare -A M1=(
#     [type]=insert|update|delete|...
#     [data]=A1
#  )
#
#  declare -a A1=(
#     'argument1'
#     'argument2'
#  )

#══════════════════════════════════╡ GLOBAL ╞═══════════════════════════════════
# Kinda dumb and hacky. Starting at (-1) so the first call to advance() will
# increment by 1, thus reading the *next* character, the first.
declare -i IDX=-1
declare -- TOKEN TOKEN_NAME PEEK1 PEEK2
# TOKEN_NAME is the name of the current token.
# TOKEN is a nameref to the token itself.

#───────────────────────────────────( nodes )───────────────────────────────────
# AST generation
declare -a REQUEST
declare -- AST_NODE
declare -i GLOBAL_AST_NUMBER=0

#═══════════════════════════════════╡ UTILS ╞═══════════════════════════════════
#────────────────────────────────( exceptions )─────────────────────────────────
function raise_parse_error {
   local loc="[${TOKEN[lineno]}:${TOKEN[colno]}]"
   echo -n "Parse Error: ${loc} "
   echo -e "Expected ${yl}$@${rst}, received ${TOKEN[type]}"

   exit -2
}


function raise_duplicate_key_error {
   local loc="[${TOKEN[lineno]}:${TOKEN[colno]}]"
   echo -n "Warning: ${loc} "
   echo -e "Key ${byl}${1@Q}${rst} already used (overwriting previous)"
   # Not an exitable error, per se. Currently this is just a 'warning' for the
   # user to be aware of.
}


# TODO: This is a pretty good implementation, as it can be used throughout the
# text, but it's unable to get the length excluding non-printing characters.
# There're a number of ways we could handle this, none of them great. Can calc
# the length of the string before passing it in. Then set $2 to the str length
# without color escapes. Can try to `sed` them out, which is insanity. Can also
# pass in the data in 3 parts:
#  - before=$1  (uncolored)
#  - error=$2   (colored)
#  - after=$3   (uncolored)
# Allows us to easily get the location of the error string in the text. This is
# a preeetttyy low priority feature. Definitely low on the list.
function pretty_print_debug_pointer {
   local loc="[${TOKEN[lineno]}:${TOKEN[colno]}]"
   local msg="$1"

   msg_length=$(( ${#msg} + 2 ))
   error_pos=$(( TOKEN[colno] + 7 ))

   # Box drawing line characters that point to the offending character.
   pointer='' ; hzsep=''

   # The error is directly below the indicator, only need a pipe.
   if [[ $msg_length -eq $error_pos ]] ; then
      offset=$(( msg_length -1 ))
      pointer='│'
   # For errors in *front* of the initial indicator.
   elif [[ $msg_length -lt $error_pos ]] ; then
      offset=$(( msg_length -1 ))
      for i in $( seq $((error_pos - msg_length -1)) ) ; do
         hzsep+='─'
      done
      pointer="└${hzsep}┐"
   # For errors *behind* the indicator.
   elif [[ $msg_length -gt $error_pos ]] ; then
      offset=$(( error_pos -1 ))
      for i in $( seq $((msg_length - error_pos -1)) ) ; do
         hzsep+='─'
      done
      pointer="┌${hzsep}┘"
   fi

   # Print it!
   echo -e "${msg} ${cy}┐${rst}"
   printf "%${offset}s${cy}${pointer}${rst}\n"  ''
   printf "${cy}query>${rst} ${INPUT_STRING}\n" ${TOKEN[lineno]-1]}
}
#───────────────────────────────────( utils )───────────────────────────────────
function t_advance {
   # Advance position in file, and position in line.
   ((IDX++))

   # Reset pointers.
   TOKEN= TOKEN_NAME= PEEK1= PEEK2=

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
         # Just a bunch of stupid `sed` and color escape garbage. It makes
         # errors print prettier.
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
   n[query]=
   n[method]=
}


function mkQuery {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -ga $node_name
   declare -g AST_NODE="$node_name"
}


function mkMethod {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -gA $node_name
   declare -g AST_NODE="$node_name"

   declare -n n=$node_name
   n[type]=
   n[data]=
}


# XXX: Right now this is unused. Not now not actually using anything that has
# an argument list. Only ever need a single argument. Should that become
# necessary in the future, is easy to implement.
function mkArgumentList {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -ga $node_name
   declare -g AST_NODE="$node_name"
}


function mkIndex {
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
   grammar_request
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
function grammar_request {
   grammar_transaction
   REQUEST+=( $AST_NODE )

   while [[ ${PEEK1[type]} == 'SEMI' ]] ; do
      munch 'SEMI'
      grammar_transaction
      REQUEST+=( $AST_NODE )
   done
}


function grammar_transaction {
   mkTransaction
   declare -- node_name=$AST_NODE
   declare -n n=$node_name

   grammar_query
   n[query]=$AST_NODE

   munch 'GREATER'
   grammar_method

   n[method]=$AST_NODE

   AST_NODE=$node_name
}


function grammar_query {
   mkQuery
   declare -- node_name=$AST_NODE
   declare -n n=$node_name

   # 1) Initial reference to root node.
   munch 'SLASH'
   grammar_root_index
   n+=( $AST_NODE )

   # 2) Additional subscription.
   while [[ "${PEEK1[type]}" == 'DOT' ]] ||
         [[ "${PEEK1[type]}" == 'L_BRACKET' ]] ; do
      munch 'DOT,L_BRACKET'

      if [[ "${TOKEN[type]}" == 'L_BRACKET' ]] ; then
         grammar_list_index
         n+=( $AST_NODE )
      elif [[ "${TOKEN[type]}" == 'DOT' ]] ; then
         grammar_dict_index
         n+=( $AST_NODE )
      fi
   done

   AST_NODE=$node_name
}


function grammar_root_index {
   mkIndex
   declare -- node_name=$AST_NODE
   declare -n d=$node_name

   d[type]='dict'
   d[data]='ROOT'

   AST_NODE=$node_name
}


function grammar_list_index {
   mkIndex
   declare -- node_name=$AST_NODE
   declare -n d=$node_name

   munch 'INTEGER'
   d[type]='list'
   d[data]=${TOKEN[data]}

   munch 'R_BRACKET'
   AST_NODE=$node_name
}


function grammar_dict_index {
   mkIndex
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
   declare -n n=$node_name

   munch 'KEYWORD'
   method=${TOKEN[data]}

   munch 'L_PAREN'
   case $method in
      'write')
            munch 'STRING'
            grammar_string
            n[data]=$AST_NODE
            ;;
      'insert')
            # TODO;XXX:
            # Kinda hate that this is the way you have to do things, but it
            # allows us to more easily allow for an optional index parameter,
            # while still letting you insert data into lists without needing to
            # pass any extra parameter.
            if [[ ${PEEK1[type]} == 'IDENTIFIER' ]] ; then
               munch 'IDENTIFIER'
               n[index]=${TOKEN[data]}
               munch 'COMMA'
            fi

            grammar_data
            n[data]=$AST_NODE
            ;;
      'update')
            grammar_data
            n[data]=$AST_NODE
            ;;
   esac
   munch 'R_PAREN'

   n[type]=$method
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
   declare -n n=$node_name
   n="${TOKEN[data]}"

   AST_NODE=$node_name
}


function grammar_list {
   mkList
   declare -- node_name=$AST_NODE
   declare -n n=$node_name

   grammar_data
   n+=( $AST_NODE )

   while [[ ${PEEK1[type]} == 'COMMA' ]] ; do
      munch 'COMMA'

      # Allow for a trailing comma at the end of a list.
      [[ ${PEEK1[type]} == 'R_BRACKET' ]] && break

      grammar_data
      n+=( $AST_NODE )
   done

   munch 'R_BRACKET'
   AST_NODE=$node_name
}


function grammar_dict {
   mkDictionary
   declare -- node_name=$AST_NODE
   declare -n n=$node_name

   # Initial assignment.
   munch 'STRING' ; local key=${TOKEN[data]}
   munch 'COLON'
   grammar_data   ; n[$key]="$AST_NODE"

   while [[ ${PEEK1[type]} == 'COMMA' ]] ; do
      munch 'COMMA'

      # Allow for a trailing comma at the end of a dict.
      [[ ${PEEK1[type]} == 'R_BRACE' ]] && break

      # Subsequent assignments.
      munch 'STRING'
      local key=${TOKEN[data]}

      if [[ -n "${n[$key]}" ]] ; then
         raise_duplicate_key_error "$key"
      fi

      munch 'COLON'
      grammar_data ; n[$key]="$AST_NODE"
   done

   munch 'R_BRACE'
   AST_NODE=$node_name
}
