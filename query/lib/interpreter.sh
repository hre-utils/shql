#!/bin/bash
# interpreter
#
# TODO: Need to actually get helpful line information into the error messages
# here. There's great error logging in the data compilation phase, why not also
# in the query compilation and parsing?
#
# I don't like how much is kicked off by the `intr_call_method` method. Things
# should be a bit more segmented. Currently it's very difficult to pull apart
# bits from down the chain.

# Query nodes & pointers
declare -- FULL_QUERY      # Nameref to current transaction's query list
declare -- QUERY           # Current query node within the full query list
declare -- METHOD          # Current transaction's method

# The above section of pointers is a little confusing. It is more clearly
# represented as such:
#
#   $REQUEST = [ TRANSACTION1, TRANSACTION2, ... ]
#                     ^
#                $transaction = ( QUERY_LIST, METHOD )
#                                     ^
#                                $FULL_QUERY = [ QUERY_NODE, QUERY_NODE, ... ]
#                                                    ^
#                                                  $QUERY

# Input data nodes
declare -a DATA_PATH       # Stack of visited parent nodes. LIFO.
declare -- DATA_NODE       # Pointer to node selected by user's query

#────────────────────────────────( exceptions )─────────────────────────────────
function raise_key_error {
   echo -n "Key Error: "
   echo -e "Key ${byl}${1@Q}${rst} not found."
   exit -7
}


function raise_index_error {
   echo -n "Index Error: "
   echo -e "Index ${byl}[${1}]${rst} out of bounds."
   exit -8
}


function raise_type_error {
   echo -n "Type Error: "
   echo -e "Operation ${yl}$1${rst} invalid on type(${yl}$2${rst})."
   exit -9
}

#════════════════════════════════╡ INTERPRETER ╞════════════════════════════════
function interpret {
   for transaction_name in "${REQUEST[@]}" ; do
      # Reset to default.
      DATA_PATH=() DATA_NODE=_DATA

      declare -n  transaction=$transaction_name
      declare -ng FULL_QUERY=${transaction[query]}

      # Locate node in tree to begin query.
      intr_get_location

      # Method.
      METHOD=${transaction[method]}
      intr_call_method
   done

   re_cache
}


function re_cache {
   declare -p _DATA >  "$PARSEFILE"
   declare -p _META >> "$PARSEFILE"
   for idx in $(seq 1 ${_META[max_node_ref]}) ; do
      declare -p "_NODE_${idx}" 2>/dev/null
   done >> "$PARSEFILE"
}


function intr_call_method {
   declare -n method=$METHOD
   case "${method[type]}" in
      'print')    intr_print  ;;
      'write')    intr_write  ;;
      'insert')   intr_insert ;;
      'update')   intr_update ;;
      'delete')   intr_delete ;;
   esac
}


function intr_get_location {
   for query_name in "${FULL_QUERY[@]}" ; do
      declare -n query=$query_name
      declare -n node=$DATA_NODE

      DATA_PATH+=( $DATA_NODE )

      # Validation: key/index errors.
      local key=${query[data]}
      local next=${node[$key]}

      # Validation: type errors.
      local node_type=$( get_type $DATA_NODE )
      if [[ $node_type != ${query[type]} ]] ; then
         raise_type_error "${query[type]} subscription" "$node_type"
      fi

      # List subscription, e.g., '[0]'
      if [[ ${query[type]} == 'list' ]] ; then
         local min=$(( -1 * ${#node[@]} ))
         local max=$(( ${#node[@]} -1 ))
         if [[ $key -lt $min || $key -gt $max ]] ; then
            raise_index_error $key
         fi
      # Dict subscription, e.g., '.bar'
      elif [[ ${query[type]} == 'dict' ]] ; then
         if [[ -z $next ]] ; then
            raise_key_error "$key"
         fi
      fi

      # Set reference to the subsequent node for the next iteration of the
      # loop.
      DATA_NODE=$next
   done

   # Set initial query pointer
   declare -n query=${FULL_QUERY[-1]}
   declare -g QUERY=${query[data]}
}


function intr_write {
   declare -n data_node=${METHOD[data]}
   declare -n path=${data_node[data]}

   local dir=$( dirname "$path" )
   mkdir -p "$dir"

   # TODO: This is a pretty shit solution. Should temporarily disable the
   # existing color, rather than re-writing the functions without it.
   regular_print_data_type $DATA_NODE > "${dir}/${path}"
}


function intr_insert {
   pass=
   #local data_node_type=$( get_type $DATA_NODE )
   #echo $data_node_type
}


function intr_update {
   declare -- data_node_type=$( get_type $DATA_NODE )
   declare -n insert_data_node=${METHOD[data]}
   declare -- insert_data=${insert_data_node[data]}

   intr_insert_data $insert_data
}


function intr_delete {
   intr_delete_type $DATA_NODE
}


function intr_print {
   print_data_type $DATA_NODE
}

#───────────────────────────────────( utils )───────────────────────────────────
function get_type {
   local t=$(declare -p $1 | awk '{print $2}')

   case $t in
      '--')    echo 'string' ;;
      '-a')    echo 'list'   ;;
      '-A')    echo 'dict'   ;;
   esac
}

#══════════════════════════════════╡ DELETE ╞═══════════════════════════════════
function intr_delete_type {
   local node_name=$1
   local node_type=$( get_type $node_name )

   case $node_type in
      'string')         intr_delete_string  $node_name ;;
      'list'|'dict')    intr_delete_array   $node_name ;;
   esac
}


function intr_delete_string {
   unset $1                               # Unset self.
   declare -n parent=${DATA_PATH[-1]}     # Nameref to parent's node
   unset parent[$QUERY]                   # Unset reference from parent

}


function intr_delete_array {
   # Bash associative arrays (dicts) and indexed arrays (lists) can be handled
   # interchangeably when removing entries. They are both indexed the same, thus
   # can be traversed the same.
   declare -- node_name=$1
   declare -n node=$node_name
   declare -- query=$QUERY

   DATA_NODE=$node_name
   DATA_PATH+=( $DATA_NODE )

   for key in "${!node[@]}" ; do
      QUERY=$key                          # Set global query string
      intr_delete_type ${node[$key]}      # Kick off recursive child deletion
      unset node[$key]                    # Unset element from array
   done

   # Pop self from stack, so we can remove this node from its parent.
   unset DATA_PATH[-1]

   declare -n parent=${DATA_PATH[-1]}     # Reference parent element from stack
   unset parent[$query]                   # Unset this element from its parent
   unset $node_name                       # Unset self.

   QUERY=$query
}

#═══════════════════════════════╡ PRETTY PRINT ╞════════════════════════════════
function indent {
   printf -- "%$(( INDNT_LVL * INDNT_SPS ))s"  ''
}


function print_data_type {
   local node_name="$1"
   local node_type=$( get_type "$node_name" )

   case $node_type in
      'string')   print_string "$node_name" ;;
      'list')     print_list   "$node_name" ;;
      'dict')     print_dict   "$node_name" ;;
   esac
}


function print_string {
   declare -n node=$1
   echo "${HI_LINK[STRING]}${node@Q}${rst}"
}


function print_list {
   declare -n node=$1

   echo "${HI_LINK[SURROUND]}[${rst}"
   ((INDNT_LVL++))

   for idx in "${!node[@]}" ; do
      declare child_name="${node[$idx]}"

      indent
      echo -n "$(print_data_type ${child_name})"

      if [[ $idx -lt $(( ${#node[@]} -1 )) ]] ; then
         echo "${HI_LINK[SURROUND]},${rst} "
      else
         echo
      fi
   done

   ((INDNT_LVL--))
   indent ; echo "${HI_LINK[SURROUND]}]${rst}"
}


function print_dict {
   echo -e "${HI_LINK[SURROUND]}{${rst}"
   ((INDNT_LVL++))

   declare node_name="$1"
   declare -n node="$node_name"

   declare -i num_keys_printed=0
   declare -i total_keys=${#node[@]}

   for child_key in "${!node[@]}" ; do
      ((num_keys_printed++))
      indent
      echo -n "${HI_LINK[KEY]}${child_key}${rst}${HI_LINK[SURROUND]}:${rst} "
      echo -n "$(print_data_type ${node[$child_key]})"

      if [[ $num_keys_printed -lt $total_keys ]] ; then
         echo "${HI_LINK[COMMA]},${rst} "
      else
         echo
      fi
   done

   ((INDNT_LVL--))
   indent ; echo "${HI_LINK[SURROUND]}}${rst}"
}

#───────────────────────────────( regular print )───────────────────────────────
function regular_print_data_type {
   local node_name="$1"
   local node_type=$( get_type "$node_name" )

   case $node_type in
      'string')   regular_print_string "$node_name" ;;
      'list')     regular_print_list   "$node_name" ;;
      'dict')     regular_print_dict   "$node_name" ;;
   esac
}


function regular_print_string {
   declare -n node=$1
   echo "${node@Q}"
}


function regular_print_list {
   declare -n node=$1

   echo "["
   ((INDNT_LVL++))

   for idx in "${!node[@]}" ; do
      declare child_name="${node[$idx]}"

      indent
      echo -n "$(regular_print_data_type ${child_name})"

      if [[ $idx -lt $(( ${#node[@]} -1 )) ]] ; then
         echo ", "
      else
         echo
      fi
   done

   ((INDNT_LVL--))
   indent ; echo "]"
}


function regular_print_dict {
   echo -e "{"
   ((INDNT_LVL++))

   declare node_name="$1"
   declare -n node="$node_name"

   declare -i num_keys_printed=0
   declare -i total_keys=${#node[@]}

   for child_key in "${!node[@]}" ; do
      ((num_keys_printed++))
      indent
      echo -n "${child_key}: "
      echo -n "$(regular_print_data_type ${node[$child_key]})"

      if [[ $num_keys_printed -lt $total_keys ]] ; then
         echo ","
      else
         echo
      fi
   done

   ((INDNT_LVL--))
   indent ; echo "}"
}

#══════════════════════════════════╡ INSERT ╞═══════════════════════════════════
function intr_insert_data {
   local node_name=$1
   local node_type=$( get_type $node_name )

   case $node_type in
      'string')         intr_insert_string $node_name ;;
      'list'|'dict')    intr_insert_array  $node_name ;;
   esac
}


function intr_insert_list {
   unset $1                               # Unset self.
   declare -n parent=${DATA_PATH[-1]}     # Nameref to parent's node
   unset parent[$QUERY]                   # Unset reference from parent
}


function intr_insert_array {
   declare -- node_name=$1
   declare -n node=$node_name
   declare -- query=$QUERY

   DATA_NODE=$node_name
   DATA_PATH+=( $DATA_NODE )

   for key in "${!node[@]}" ; do
      QUERY=$key                          # Set global query string
      intr_delete_type ${node[$key]}      # Kick off recursive child deletion
      unset node[$key]                    # Unset element from array
   done

   # Pop self from stack, so we can remove this node from its parent.
   unset DATA_PATH[-1]

   declare -n parent=${DATA_PATH[-1]}     # Reference parent element from stack
   unset parent[$query]                   # Unset this element from its parent
   unset $node_name                       # Unset self.

   QUERY=$query
}
