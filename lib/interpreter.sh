#!/bin/bash
# interpreter
#
# TODO:
# 1) Need to actually get helpful line information into the error messages
# here. There's great error logging in the data compilation phase, why not also
# in the query compilation and parsing?
#
# 2) When deleting the _DATA[ROOT] node, we lose the [ROOT] propr on _DATA.
# Unable to query or insert back onto it. Special case to re-establisht the
# key?
#
# 3) Profiling... what's eating up all the time.
#     a. any subprocessed:   $(...)
#     b. print operations? make a buffer to append to, print once at the
#        end--no reason printing should be on the fly
#     c. dicts are currently very expensive, find out why

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

# Current level of indentation
declare -i INDNT_LVL=0

## PROFILING
declare -- WRITE_BUFFER=''
declare -- DATA_NODE_TYPE

#────────────────────────────────( exceptions )─────────────────────────────────
function raise_key_error {
   echo -n "Key Error: " 1>&2
   echo -e "Key ${byl}${1@Q}${rst} not found." 1>&2
   exit -7
}


function raise_index_error {
   echo -n "Index Error: " 1>&2
   echo -e "Index ${byl}[${1}]${rst} out of bounds." 1>&2
   exit -8
}


function raise_type_error {
   echo -n "Type Error: " 1>&2
   echo -e "Operation ${yl}$1${rst} invalid on type(${yl}$2${rst})." 1>&2
   exit -9
}


function raise_insert_dict_error {
   echo -n  "Key Error: " 1>&2
   echo -ne "Key ${byl}${1@Q}${rst} already exists. " 1>&2
   echo -e  "Perhaps you meant ${yl}update()${rst}?" 1>&2
   exit -10
}


function raise_insert_string_error {
   echo -n  "Type Error: " 1>&2
   echo -ne "Unable to insert into a string. " 1>&2
   echo -e  "Perhaps you meant ${yl}update()${rst}?" 1>&2
   exit -11
}

function raise_insert_list_index_error {
   echo -n  "Index Error: " 1>&2
   echo -ne "Index ${byl}[${1}]${rst} out of bounds." 1>&2
   echo -e  "Perhaps you meant ${yl}append()${rst} or ${yl}prepend()${rst}?" 1>&2
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

      get_type $DATA_NODE
      local node_type=$DATA_NODE_TYPE

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

   get_type $DATA_NODE
   local data_node_type=$DATA_NODE_TYPE

   case $data_node_type in
      'string')       echo ${#node}    ;;
      'list'|'dict')  echo ${#node[@]} ;;
      *) raise_type_error "len()" "$data_node_type"
   esac
}


function intr_write {
   # TODO: This is a pretty shit solution. Should temporarily disable the
   # existing color, rather than re-writing the functions without it.

   declare -n node=${METHOD[data]}
   declare -- path=${node[data]}

   mkdir -p "$( dirname "$path" )"

   regular_print_data_by_type $DATA_NODE
   echo "$WRITE_BUFFER" #> "${path}"
}


function intr_insert {
   declare -n node=$DATA_NODE

   get_type $DATA_NODE
   declare -- data_node_type=$DATA_NODE_TYPE

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
   declare -- insert_data_node=${METHOD[data]}

   intr_delete_by_type $DATA_NODE
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
   declare -- insert_data_node=${METHOD[data]}

   get_type $DATA_NODE
   declare -- data_node_type=$DATA_NODE_TYPE

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
   declare -- insert_data_node=${METHOD[data]}

   get_type $DATA_NODE
   declare -- data_node_type=$DATA_NODE_TYPE

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
      '--')    DATA_NODE_TYPE='string'  ;;
      '-a')    DATA_NODE_TYPE='list'    ;;
      '-A')    DATA_NODE_TYPE='dict'    ;;
      '-i')    DATA_NODE_TYPE='int'     ;;
      '-n')    DATA_NODE_TYPE='nameref' ;;
   esac
}

#══════════════════════════════════╡ DELETE ╞═══════════════════════════════════
function intr_delete_by_type {
   local node_name=$1

   get_type $node_name
   local node_type=$DATA_NODE_TYPE

   case $node_type in
      'string'|'int')   intr_delete_string  $node_name ;;
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
   
   get_type $node_name
   local node_type=$DATA_NODE_TYPE

   case $node_type in
      'string'|'int')  print_string "$node_name" ;;
      'list')          print_list   "$node_name" ;;
      'dict')          print_dict   "$node_name" ;;
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

   get_type $node_name
   node_type=$DATA_NODE_TYPE

   case $node_type in
      'string'|'int')  regular_print_string "$node_name" ;;
      'list')          regular_print_list   "$node_name" ;;
      'dict')          regular_print_dict   "$node_name" ;;
   esac
}


function regular_print_string {
   declare -n node=$1
   WRITE_BUFFER+="${node@Q}"
}


function regular_print_list {
   declare -n node=$1

   WRITE_BUFFER+='['
   for idx in "${!node[@]}" ; do
      declare child_name="${node[$idx]}"
      regular_print_data_by_type ${child_name}
      WRITE_BUFFER+=','
   done
   WRITE_BUFFER+=']'
}


function regular_print_dict {
   WRITE_BUFFER+='{'

   declare node_name="$1"
   declare -n node="$node_name"

   for child_key in "${!node[@]}" ; do
      WRITE_BUFFER+="${child_key}: "
      regular_print_data_by_type ${node[$child_key]}
      WRITE_BUFFER+=','
   done

   WRITE_BUFFER+='}'
}

#══════════════════════════════════╡ INSERT ╞═══════════════════════════════════
function intr_insert_by_type {
   local node_name=$1

   get_type $node_name
   local node_type=$DATA_NODE_TYPE

   case $node_type in
      'string'|'int') intr_insert_string $node_name ;;
      'list'|'dict')  intr_insert_array  $node_name ;;
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
