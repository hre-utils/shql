#──────────────────────────────────( global )───────────────────────────────────
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

#────────────────────────────────( exceptions )─────────────────────────────────
function raise_parse_error {
   local loc="[${TOKEN[lineno]}:${TOKEN[colno]}]"
   echo -n "Parse Error: ${loc} " 1>&2
   echo -e "Expected ${byl}${@}${rst}, received ${byl}${TOKEN[type]}${rst}." 1>&2

   exit -2
}


function raise_duplicate_key_error {
   local loc="[${TOKEN[lineno]}:${TOKEN[colno]}]"
   echo -n "Warning: ${loc} " 1>&2
   echo -e "Key ${byl}${1@Q}${rst} already used (overwriting previous)" 1>&2
   # Not an exitable error, per se. Currently this is just a 'warning' for the
   # user to be aware of.
}


function raise_invalid_key_error {
   local loc="[${TOKEN[lineno]}:${TOKEN[colno]}]"
   echo -n "Key Error: ${loc} " 1>&2
   echo -e "Key ${byl}${1@Q}${rst} format invalid. Must be a bash 'word'." 1>&2

   exit -3
}

#───────────────────────────────────( utils )───────────────────────────────────
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


function validate_key {
   declare -- key="$1"
   [[ "$key" =~ ^[[:alpha:]_][[:alnum:]_]*$ ]]
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


function t_advance {
   # Advance position in file, and position in line.
   local bf
   ((++IDX))

   # Reset pointers.
   TOKEN= tPEEK1= tPEEK2=

   if [[ ${IDX} -lt ${#TOKENS[@]} ]] ; then
      declare -gn TOKEN=${TOKENS[IDX]}
   fi

   # Lookahead +1.
   if [[ ${IDX} -lt $((${#TOKENS[@]}-1)) ]] ; then
      declare t1=${TOKENS[IDX+1]}
      declare -gn tPEEK1=$t1
   fi

   # Lookahead +2.
   if [[ ${IDX} -lt $((${#TOKENS[@]}-2)) ]] ; then
      declare t2=${TOKENS[IDX+2]}
      declare -gn tPEEK2=$t2
   fi
}

#═════════════════════════════════╡ AST NODES ╞═════════════════════════════════
#────────────────────────────────( data nodes )─────────────────────────────────
function mkInteger {
   ((GLOBAL_AST_NUMBER++))
   local node_name="${NODE_PREFIX}${GLOBAL_AST_NUMBER}"
   declare -gi $node_name
   declare -g  AST_NODE="$node_name"
}


function mkString {
   ((GLOBAL_AST_NUMBER++))
   local node_name="${NODE_PREFIX}${GLOBAL_AST_NUMBER}"
   declare -g $node_name
   declare -g AST_NODE="$node_name"
}


function mkList {
   ((GLOBAL_AST_NUMBER++))
   local node_name="${NODE_PREFIX}${GLOBAL_AST_NUMBER}"
   declare -ga $node_name
   declare -g  AST_NODE="$node_name"

   # An array declared with only `declare -a arr`, but no value, will not be
   # printed by `declare -p ${!arr*}`. Requires to be set to at least an empty
   # array.
   declare -n  node=$node_name
   node=()
}


function mkDictionary {
   ((GLOBAL_AST_NUMBER++))
   local node_name="${NODE_PREFIX}${GLOBAL_AST_NUMBER}"
   declare -gA $node_name
   declare -g  AST_NODE="$node_name"

   declare -n  node=$node_name
   node=()
}

#────────────────────────────────( query nodes )────────────────────────────────
function mkTransaction {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -gA $node_name
   declare -g  AST_NODE="$node_name"

   declare -n node=$node_name
   n[query]=
   n[method]=
}


function mkQuery {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -ga $node_name
   declare -g  AST_NODE="$node_name"
}


function mkIndex {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -gA $node_name
   declare -g  AST_NODE="$node_name"

   declare -n node=$node_name
   n[type]=
   n[data]=
}


function mkMethod {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -gA $node_name
   declare -g  AST_NODE="$node_name"

   declare -n node=$node_name
   n[data]=
   n[type]=
   n[index]=
   n[index_type]=
}


function mkQuery {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -ga $node_name
   declare -g  AST_NODE="$node_name"
}


function mkIndex {
   ((GLOBAL_AST_NUMBER++))
   local node_name="_QUERY_NODE_${GLOBAL_AST_NUMBER}"
   declare -gA $node_name
   declare -g  AST_NODE="$node_name"

   declare -n node=$node_name
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
   declare -g  AST_NODE="$node_name"
}

#═════════════════════════════╡ GRAMMAR FUNCTIONS ╞═════════════════════════════
#───────────────────────────────( data grammar )────────────────────────────────
function grammar_root {
   # Root of the dataset may only be a list or a dict. No sense in using a JSON-
   # esque database if you're only holding a single string.
   munch 'L_BRACE,L_BRACKET'

   case ${TOKEN[type]} in
      'L_BRACE')   grammar_dict   ;;
      'L_BRACKET') grammar_list   ;;
   esac
}


function grammar_data {
   munch 'INTEGER,STRING,L_BRACE,L_BRACKET'

   case ${TOKEN[type]} in
      'STRING')    grammar_string ;;
      'INTEGER')   grammar_int ;;
      'L_BRACE')   grammar_dict   ;;
      'L_BRACKET') grammar_list   ;;
   esac
}


function grammar_string {
   mkString
   declare -n node=$AST_NODE
   node=${TOKEN[data]}
}


function grammar_int {
   mkInteger
   declare -n node=$AST_NODE
   node=${TOKEN[data]}
}


function grammar_list {
   mkList
   declare -- node_name=$AST_NODE
   declare -n node=$node_name

   until [[ ${tPEEK1[type]} == 'R_BRACKET' ]] ; do
      grammar_data
      node+=( $AST_NODE )

      # This should serve the same function as the previous approach, however
      # it also allows for the user to pass an empty list. Previous iteration
      # required some initial data in lists and dicts.
      if [[ ${tPEEK1[type]} == 'COMMA' ]] ; then
         munch 'COMMA'
      fi
   done

   munch 'R_BRACKET'
   AST_NODE=$node_name
}


function grammar_dict {
   mkDictionary
   declare -- node_name=$AST_NODE
   declare -n node=$node_name

   until [[ ${tPEEK1[type]} == 'R_BRACE' ]] ; do
      # TODO: currently requires string keys. Is this a holdover from JSON that
      # we want to keep? Is there a good argument to be made for having non-
      # string keys?
      munch 'STRING'
      local key=${TOKEN[data]}

      if [[ -n "${node[$key]}" ]] ; then
         raise_duplicate_key_error "$key"
      fi

      if ! validate_key "$key" ; then
         raise_invalid_key_error "$key"
      fi

      munch 'COLON'
      grammar_data
      node[$key]=$AST_NODE

      if [[ ${tPEEK1[type]} == 'COMMA' ]] ; then
         munch 'COMMA'
      fi
   done

   munch 'R_BRACE'
   AST_NODE=$node_name
}

#───────────────────────────────( query grammar )───────────────────────────────
function grammar_request {
   grammar_transaction
   REQUEST+=( $AST_NODE )

   while [[ ${tPEEK1[type]} == 'SEMI' ]] ; do
      munch 'SEMI'
      grammar_transaction
      REQUEST+=( $AST_NODE )
   done
}


function grammar_transaction {
   mkTransaction
   declare -- node_name=$AST_NODE
   declare -n node=$node_name

   grammar_query
   node[query]=$AST_NODE

   munch 'GREATER'
   grammar_method

   node[method]=$AST_NODE
   AST_NODE=$node_name
}


function grammar_query {
   mkQuery
   declare -- node_name=$AST_NODE
   declare -n node=$node_name

   # 1) Initial reference to root node.
   munch 'SLASH'
   grammar_root_index
   node+=( $AST_NODE )

   # 2) Additional subscription.
   while [[ "${tPEEK1[type]}" == 'DOT' ]] ||
         [[ "${tPEEK1[type]}" == 'L_BRACKET' ]] ; do
      munch 'DOT,L_BRACKET'

      if [[ "${TOKEN[type]}" == 'L_BRACKET' ]] ; then
         grammar_list_index
         node+=( $AST_NODE )
      elif [[ "${TOKEN[type]}" == 'DOT' ]] ; then
         grammar_dict_index
         node+=( $AST_NODE )
      fi
   done

   AST_NODE=$node_name
}


function grammar_root_index {
   mkIndex
   declare -- node_name=$AST_NODE
   declare -n node=$node_name

   node[type]='dict'
   node[data]='ROOT'

   AST_NODE=$node_name
}


function grammar_list_index {
   mkIndex
   declare -- node_name=$AST_NODE
   declare -n node=$node_name

   munch 'INTEGER'
   node[type]='list'
   node[data]=${TOKEN[data]}

   munch 'R_BRACKET'
   AST_NODE=$node_name
}


function grammar_dict_index {
   mkIndex
   declare -- node_name=$AST_NODE
   declare -n node=$node_name

   munch 'IDENTIFIER'
   node[type]='dict'
   node[data]="${TOKEN[data]}"

   AST_NODE=$node_name
}


function grammar_method {
   mkMethod
   declare -- node_name=$AST_NODE
   declare -n node=$node_name

   munch 'KEYWORD'
   method=${TOKEN[data]}

   # Operations that do not take an argument:
   #  - len()
   #  - print()
   #  - delete()

   munch 'L_PAREN'
   case $method in
      'write')
            munch 'STRING'
            grammar_string
            node[data]=$AST_NODE
            ;;
      'insert')
            munch 'STRING,INTEGER'
            node[index]=${TOKEN[data]}
            node[index_type]=${TOKEN[type]}

            munch 'COMMA'

            grammar_data
            node[data]=$AST_NODE
            ;;
      'update')
            grammar_data
            node[data]=$AST_NODE
            ;;
      'prepend'|'append')
            grammar_data
            node[data]=$AST_NODE
            ;;
   esac
   munch 'R_PAREN'

   node[type]=$method
   AST_NODE=$node_name
}
