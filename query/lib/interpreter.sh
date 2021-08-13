#!/bin/bash
# interpreter

declare -a NODE_PATH       # List of traveled nodes
declare -- LOCATION        # This transaction's location query list
declare -- METHOD          # This transaction's method

declare -- PARENT          # Pointer to parent of currently 'selected' node
declare -- QUERY           # Current 'query' within the location[]

#────────────────────────────────( exceptions )─────────────────────────────────
function raise_key_error {
   echo -e "Key Error: Key ${byl}${1@Q}${rst} not found."
   exit -7
}


function raise_index_error {
   echo -e "Index Error: Index ${byl}[${1}]${rst} out of bounds."
   exit -8
}


function raise_type_error {
   echo -n "Type Error: "
   echo -e "Operation ${yl}$1${rst} invalid on type(${yl}$2${rst})."
   exit -9
}

#════════════════════════════════╡ INTERPRETER ╞════════════════════════════════
function interpret {
   for transaction_node_name in "${TRANSACTIONS[@]}" ; do
      # Reset node list to default.
      NODE_PATH=()

      declare -n transaction=$transaction_node_name
      LOCATION=${transaction[location]}
      METHOD=${transaction[method]}

      intr_method_map
   done
}


function intr_method_map {
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
   # There are only 2 types of subscription:
   #  1. lists,  foo[0]
   #  2. dicts,  foo.bar
   # Strings are not subscriptable, they are a terminal node. Though how should
   # we track the _ROOT node?

   declare -n location=$LOCATION

   for query_name in "${location[@]}" ; do
      declare -n query=$query_name

      #───────────────────────( initial root node )─────────────────────────────
      if [[ ${query[type]} == '_ROOT' ]] ; then
         declare -n root=${query[data]}
         NODE_PATH+=( $root )
         continue
      fi

      #───────────────────( subsequent query nodes )─────────────────────────
      declare -- cur_node=${NODE_PATH[-1]}
      declare -n node=$cur_node

      # Validation: type errors.
      local node_type=$( get_type $cur_node )
      if [[ $node_type != ${query[type]} ]] ; then
         raise_type_error "${query[type]} subscription" "$node_type"
      fi

      # Validation: key/index errors.
      local key=${query[data]}

      # List subscription, e.g., '[0]'
      if [[ ${query[type]} == 'list' ]] ; then
         local min=$(( -1 * ${#node[@]} ))
         local max=$(( ${#node[@]} -1 ))
         if [[ $key -lt $min || $key -gt $max ]] ; then
            raise_index_error $key
         fi
      # Dict subscription, e.g., '.bar'
      elif [[ ${query[type]} == 'dict' ]] ; then
         if [[ -z ${node[$key]} ]] ; then
            raise_key_error "$key"
         fi
      fi

      # Finally... append node to path.
      NODE_PATH+=( ${node[$key]} )
   done
}


function intr_print {
   local pass
}


function intr_write {
   local pass
}


function intr_insert {
   local pass
}


function intr_update {
   local pass
}


function intr_delete {
   intr_get_location

   PARENT=$_ROOT
   ent_delete_type ${NODE_PATH[-1]}
}


function intr_print {
   intr_get_location
   print_data_type ${NODE_PATH[-1]}
}

#───────────────────────────────────( utils )───────────────────────────────────
function get_type {
   local t=$(declare -p "$1" | awk '{print $2}')

   case $t in
      '--')    echo 'string' ;;
      '-a')    echo 'list'   ;;
      '-A')    echo 'dict'   ;;
   esac
}

#══════════════════════════════════╡ DELETE ╞═══════════════════════════════════
function ent_delete_type {
   local node_name=$1
   local node_type=$( get_type "$node_name" )

   case $node_type in
      'string')   ent_delete_type_string "$node_name" ;;
      'list')     ent_delete_type_list   "$node_name" ;;
      'dict')     ent_delete_type_dict   "$node_name" ;;
   esac
}


function ent_delete_type_string {
   unset "$1"
   declare -n parent=$PARENT
   declare -n location=$LOCATION

   echo "location[${location[@]}]"
   for name in "${location[@]}" ; do
      declare -n n=$name
      echo "${n[@]}"
   done

   unset parent[$QUERY]
}


function ent_delete_type_list {
   local parent=$PARENT
   local query=$QUERY

   local node_name=$1
   declare -n node=$node_name

   PARENT=$node_name

   for idx in "${!node[@]}" ; do
      QUERY=$idx
      ent_delete_type ${node[$idx]}
      unset node[$idx]
   done

   PARENT=$parent
   QUERY=$query

   declare -n p=$PARENT
   unset p[$QUERY]

   unset $node_name
}


function ent_delete_type_dict {
   local parent=$PARENT
   local query=$QUERY

   local node_name=$1
   declare -n node=$node_name

   PARENT=$node_name

   for key in "${!node[@]}" ; do
      QUERY=$key
      ent_delete_type ${node[$key]}
      unset node[$key]
   done

   PARENT=$parent
   QUERY=$query

   declare -n p=$PARENT
   unset p[$QUERY]

   unset $node_name
}

#═══════════════════════════════╡ PRETTY PRINT ╞════════════════════════════════
function indent {
   printf -- "%$(( INDNT_LVL * INDNT_SPS ))s"  ''
}


function print_data_type {
   local node_name="$1"
   local node_type=$( get_type "$node_name" )

   case $node_type in
      'string')   pp_string "$node_name" ;;
      'list')     pp_list   "$node_name" ;;
      'dict')     pp_dict   "$node_name" ;;
   esac
}


function pp_string {
   declare node_name="$1"
   declare -n node="$node_name"
   echo "${HI_STRING}${node@Q}${rst}"
}


function pp_list {
   declare node_name="$1"
   declare -n node="$node_name"

   echo "${HI_SURROUND}[${rst}"
   ((INDNT_LVL++))

   for idx in "${!node[@]}" ; do
      declare child_name="${node[$idx]}"

      indent
      echo -n "$(print_data_type ${child_name})"

      if [[ $idx -lt $(( ${#node[@]} -1 )) ]] ; then
         echo "${HI_SURROUND},${rst} "
      else
         echo
      fi
   done

   ((INDNT_LVL--))
   indent ; echo "${HI_SURROUND}]${rst}"
}


function pp_dict {
   echo -e "${HI_SURROUND}{${rst}"
   ((INDNT_LVL++))

   declare node_name="$1"
   declare -n node="$node_name"

   declare -i num_keys_printed=0
   declare -i total_keys=${#node[@]}

   for child_key in "${!node[@]}" ; do
      ((num_keys_printed++))
      indent
      echo -n "${HI_KEY}${child_key}${rst}${HI_SURROUND}:${rst} "
      echo -n "$(print_data_type ${node[$child_key]})"

      if [[ $num_keys_printed -lt $total_keys ]] ; then
         echo "${HI_COMMA},${rst} "
      else
         echo
      fi
   done

   ((INDNT_LVL--))
   indent ; echo "${HI_SURROUND}}${rst}"
}
