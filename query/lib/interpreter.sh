#!/bin/bash
# interpreter
#
# TODO:
# 1) Need to actually get helpful line information into the error messages
# here. There's great error logging in the data compilation phase, why not also
# in the query compilation and parsing?
#
# 2) I don't like how much is kicked off by the `intr_call_method` method.
# Things should be a bit more segmented. Currently it's very difficult to pull
# apart bits from down the chain.
#
# 3) When deleting the _DATA[ROOT] node, we lose the [ROOT] propr on _DATA.
# Unable to query or insert back onto it. Special case to re-establisht the
# key?

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


function raise_insert_dict_error {
   echo -n  "Key Error: "
   echo -ne "Key ${byl}${1@Q}${rst} already exists. "
   echo -e  "Perhaps you meant ${yl}update()${rst}?"
   exit -10
}


function raise_insert_string_error {
   echo -n  "Type Error: "
   echo -ne "Unable to insert into a string. "
   echo -e  "Perhaps you meant ${yl}update()${rst}?"
   exit -11
}

function raise_insert_list_index_error {
   echo -n  "Index Error: "
   echo -e  "Index ${byl}[${1}]${rst} out of bounds."
   echo -e  "Perhaps you meant ${yl}append()${rst} or ${yl}prepend()${rst}?"
   exit -12
}


#════════════════════════════════╡ INTERPRETER ╞════════════════════════════════
function interpret {
   for transaction_name in "${REQUEST[@]}" ; do
      # Reset to default.
      DATA_PATH=() DATA_NODE=_DATA

      declare -n  transaction=$transaction_name
      declare -gn FULL_QUERY=${transaction[query]}

      # Locate node in tree to begin query.
      intr_get_location

      # Set initial pointers.
      declare -n  query=${FULL_QUERY[-1]}
      declare -g  QUERY=${query[data]}
      declare -gn METHOD=${transaction[method]}

      # Method.
      intr_call_method
   done

   re_cache
}


function re_cache {
   (
      declare -p _META
      declare -p _DATA
      if [[ -n ${!_NODE_*} ]] ; then
         declare -p ${!_NODE_*}
      fi
   ) | sort -V -k3 > "$PARSEFILE"
}


function intr_call_method {
   case "${METHOD[type]}" in
      'len')      intr_len     ;;
      'write')    intr_write   ;;
      'print')    intr_print   ;;
      'insert')   intr_insert  ;;
      'update')   intr_update  ;;
      'delete')   intr_delete  ;;
      'append')   intr_append  ;;
      'prepend')  intr_prepend ;;
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
}


function intr_len {
   declare -n node=$DATA_NODE
   declare -- data_node_type=$( get_type $DATA_NODE )

   case $data_node_type in
      'string')       echo ${#node}    ;;
      'list'|'dict')  echo ${#node[@]} ;;
   esac
}


function intr_write {
   declare -n data_node=${METHOD[data]}
   declare -- path=${data_node[data]}

   local dir=$( dirname "$path" )
   mkdir -p "$dir"

   # TODO: This is a pretty shit solution. Should temporarily disable the
   # existing color, rather than re-writing the functions without it.
   regular_print_data_by_type $DATA_NODE > "${dir}/${path}"
}


function intr_insert {
   declare -n node=$DATA_NODE
   declare -- data_node_type=$( get_type $DATA_NODE )

   declare -- insert_data_node=${METHOD[data]}
   declare -- index=${METHOD[index]}

   case $data_node_type in
      'string')
               raise_insert_string_error
               ;;

      'list')
               # Validation: must be numerical index
               if [[ ${METHOD[index_type]} != 'INTEGER' ]] ; then
                  raise_type_error "${METHOD[type]} subscription" 'list'
               fi

               # Validation: must be within bounds
               local -i min=$(( -1 * ${#node[@]} ))
               local -i max=$(( ${#node[@]} -1 ))
               if [[ $index -lt $min || $index -gt $max ]] ; then
                  raise_insert_list_index_error "$index"
               fi

               # We need to shift all elements from node[$index] up one, making
               # space to insert the node into the middle. I see two ways of
               # doing this:
               #  1. Shift up, insert at $index
               #     a. Save the upper & lower halves of the array
               #     b. Set the array to equal (LOWER dummy_var UPPER)
               #     c. Unset the dummy var, leaving the spot open
               #  2. Iter backwards, move everything up
               #     a. Get length of the array
               #     b. Iter through decrementing until we hit the $index
               #     c. Shift every element's $index +1

               declare -i remaining=$(( ${#node[@]} - index ))
               declare -a lower=( "${node[@]::$index}" )
               declare -a upper=( "${node[@]:$index:$remaining}" )

               node=( "${lower[@]}"  'placeholder'  "${upper[@]}" )
               unset node[$index]
               ;;

      'dict')
               if [[ ${METHOD[index_type]} != 'STRING' ]] ; then
                  raise_type_error "${METHOD[type]} subscription" 'list'
               fi

               # Validation: duplicate dict key.
               if [[ -n ${node[$index]} ]] ; then
                  raise_insert_dict_error "$index"
               fi
               ;;
   esac

   # TODO;XXX:
   # This is super hacky, and I don't love how it works. We don't actually need
   # to make a real node. We just need to append SOMETHING to the end of the
   # FULL_QUERY, and manually set QUERY=$index. Must also shift the data path
   # to the current node, rather than the parent. We want it to add the data
   # to the *existing* node we're working with, not it's parent.
   FULL_QUERY+=( _PSEUDO_QUERY )
   DATA_PATH+=( $DATA_NODE )
   QUERY=$index

   intr_insert_by_type $insert_data_node
}



function intr_update {
   declare -- data_node_type=$( get_type $DATA_NODE )
   declare -- insert_data_node=${METHOD[data]}

   # TODO: Turns out this will be a bit more of a complex operation than I
   # though before. Need to first recursively delete everything under the
   # existing node we are updating. But we *can't* delete the key to it...
   # Oh wait, yes we can. Turns out update is exactly the same as a full
   # recursive delete, followed by an insert() with the original key.
   # Interesting.
   intr_delete_by_type $DATA_NODE

   # Then can drop the new parent node into the original location, using the
   # original $QUERY.
   intr_insert_by_type $insert_data_node
}


function intr_delete {
   intr_delete_by_type $DATA_NODE
}


function intr_print {
   print_data_by_type $DATA_NODE
}


function intr_append {
   declare -n node=$DATA_NODE

   declare -- data_node_type=$( get_type $DATA_NODE )
   declare -- insert_data_node=${METHOD[data]}

   # Validation: must be list.
   if [[ $data_node_type != 'list' ]] ; then
      raise_type_error 'append()' $data_node_type
   fi

   FULL_QUERY+=( _PSEUDO_QUERY )
   DATA_PATH+=( $DATA_NODE )
   QUERY=${#node[@]}

   intr_insert_by_type $insert_data_node
}


function intr_prepend {
   declare -n node=$DATA_NODE

   declare -- data_node_type=$( get_type $DATA_NODE )
   declare -- insert_data_node=${METHOD[data]}

   # Validation: must be list.
   if [[ $data_node_type != 'list' ]] ; then
      raise_type_error 'prepend()' $data_node_type
   fi

   node=( 'placeholder' "${node[@]}" )

   FULL_QUERY+=( _PSEUDO_QUERY )
   DATA_PATH+=( $DATA_NODE )
   QUERY=0

   intr_insert_by_type $insert_data_node
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
function intr_delete_by_type {
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
      intr_delete_by_type ${node[$key]}   # Kick off recursive child deletion
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


function print_data_by_type {
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
      echo -n "$(print_data_by_type ${child_name})"

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
      echo -n "$(print_data_by_type ${node[$child_key]})"

      if [[ $num_keys_printed -lt $total_keys ]] ; then
         echo "${HI_LINK[COMMA]},${rst} "
      else
         echo
      fi
   done

   ((INDNT_LVL--))
   indent ; echo "${HI_LINK[SURROUND]}}${rst}"
}

#═══════════════════════════════╡ REGULAR PRINT ╞═══════════════════════════════
function regular_print_data_by_type {
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
      echo -n "$(regular_print_data_by_type ${child_name})"

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
      echo -n "$(regular_print_data_by_type ${node[$child_key]})"

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
function intr_insert_by_type {
   local node_name=$1
   local node_type=$( get_type $node_name )

   case $node_type in
      'string') intr_insert_string $node_name ;;
      'list'|'dict') intr_insert_array  $node_name ;;
   esac
}


function intr_convert_query_node {
   declare -- node_name=$1
   declare -- new_name=$2

   # Dump existing declaration.
   declare -- declaration=$( declare -p $node_name )

   # Make it actually global. By default, all $(declare -p) dumps have the
   # local version of the variable/array declaration.
   declaration=$( sed -E 's,(declare\s-)[-]?([Aa])?,\1\2g,' <<< "$declaration" )

   # Source it back in with the updated node name.
   source <( echo "${declaration/${node_name}/$new_name}" )

   # Remove old _QUERY node.
   unset $node_name
}


function intr_insert_string {
   declare -- node_name=$1

   # Increment existing max node counter. Ensure we're not stomping on an
   # existing data node names. Especially with two back-to-back insert
   # operations.
   declare -n idx=_META[max_node_ref]
   ((++idx))

   # Define new name, effectively appending to the existing data node set.
   declare -- new_name="_NODE_${idx}"
   intr_convert_query_node $node_name $new_name

   # Replace parent's pointer to the freshly created node.
   declare -n parent=${DATA_PATH[-1]}
   parent[$QUERY]=$new_name
}


function intr_insert_array {
   # Same sorta methodology here as in the intr_delete_array. It's very similar.
   declare -- node_name=$1
   declare -- query=$QUERY

   # Increment existing max node counter. Ensure we're not stomping on an
   # existing data node names. Especially with two back-to-back insert
   # operations.
   declare -n idx=_META[max_node_ref]
   ((++idx))

   # Define new name, effectively appending to the existing data node set.
   declare -- new_name="_NODE_${idx}"
   intr_convert_query_node $node_name $new_name

   DATA_NODE=$new_name
   DATA_PATH+=( $DATA_NODE )

   declare -n node=$new_name
   for key in "${!node[@]}" ; do
      QUERY=$key
      intr_insert_by_type ${node[$key]}
   done

   # Pop self from stack.
   unset DATA_PATH[-1]

   declare -n parent=${DATA_PATH[-1]}
   parent[$query]=$new_name

   # Restore prior global query.
   QUERY=$query
}
