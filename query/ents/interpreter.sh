#!/bin/bash

# Initial node
NODE_NAME=_NODE_1
NODE_PREV=

# TODO
# I wonder if it would help to also include with the cache a section of meta
# information, to make insertions into the existing data easier. Right now we
# can easily distinguish between original data (prefixed by _NODE_) and query
# data (prefixed by _QUERY_NODE_). However what if we perform an insertion, then
# wish to insert a *second* value. The same _QUERY_NODE_ name will be used.
# When written, must swap all _QUERY_NODE(s) to _NODE(s). Having meta information
# such as "what is that files max(GLOBAL_NODE_COUNTER)" would allow us to simply
# iterate through all _QUERY_ nodes, and replace them with _NODES_ beginning at
# the previous max. Each insert or modify operation will utilize this. We cannot
# rely on nodes within the data having a sequential number, as intermediate ones
# may be deleted.
#
# Allow for multiple statements on a line. For example:
#  query>  /here[0] > delete(), / > print(), / > write()

#────────────────────────────────( exceptions )─────────────────────────────────
function raise_key_error {
   #local loc="[${TOKEN[lineno]}:${TOKEN[colno]}]"
   #echo -n "Key Error: ${loc} "
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
   case "${METHOD[type]}" in
      'insert')   intr_insert ;;
      'update')   intr_update ;;
      'delete')   intr_delete ;;
      '')         intr_print  ;;
   esac
}


function intr_get_location {
   # TODO:
   # I don't like how this uses a global NODE_NAME. It is done because we cannot
   # raise exceptions in a subshell. The subshell's `exit` statement will only
   # exit that fork.
   for loc_name in "${LOCATION[@]}" ; do
      # Tracking the previously set node, allowing us to perform deletions or
      # insertions on the node referring TO this one.
      NODE_PREV=$NODE_NAME

      declare -n loc=$loc_name
      declare -n node=$NODE_NAME

      # Validation: type errors.
      local node_type=$( get_type $NODE_NAME )
      if [[ $node_type != ${loc[type]} ]] ; then
         raise_type_error "${loc[type]} subscription" "$node_type"
      fi

      # Validation: key/index errors.
      local key=${loc[data]}
      if [[ ${loc[type]} == 'list' ]] ; then
         local min=$(( -1 * ${#node[@]} ))
         local max=$(( ${#node[@]} -1 ))
         if [[ $key -lt $min || $key -gt $max ]] ; then
            raise_index_error $key
         fi
         NODE_NAME=${node[$key]}
      elif [[ ${loc[type]} == 'dict' ]] ; then
         NODE_NAME=${node[$key]}
         if [[ -z $NODE_NAME ]] ; then
            raise_key_error "$key"
         fi
      fi
   done
}


function intr_insert {
   local pass
}


function intr_update {
   local pass
}


function intr_delete {
   intr_get_location

   ent_delete $NODE_NAME 
   print_data_type _NODE_1
}


function intr_print {
   intr_get_location
   print_data_type $NODE_NAME
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

# THINKIES: wonder if we can use a sort of 'listener' architecture. Create
# something that just walks the tree, then blasts to all subscribed listeners
# who decide what to do with it. I feel like if this is something that's non-
# trivial to implement correctly in Python, it will be next to impossible in
# Bash. Challenge accepted? Perhaps for another day.

#══════════════════════════════════╡ DELETE ╞═══════════════════════════════════
function ent_delete {
   ent_delete_type "$1"
   if [[ -n $NODE_PREV ]] ; then
      declare -n prev=$NODE_PREV
      unset prev[$1]
   fi
}


function ent_delete_type {
   local node_name="$1"
   local node_type=$( get_type "$node_name" )

   case $node_type in
      'string')   ent_delete_type_string "$node_name" ;;
      'list')     ent_delete_type_list   "$node_name" ;;
      'dict')     ent_delete_type_dict   "$node_name" ;;
   esac
}


function ent_delete_type_string {
   unset $1
}


function ent_delete_type_list {
   declare node_name="$1"
   declare -n node="$node_name"
   
   for idx in "${!node[@]}" ; do
      ent_delete_type ${node[$idx]}
   done

   unset $node_name
}


function ent_delete_type_dict {
   declare node_name="$1"
   declare -n node="$node_name"

   for child_key in "${!node[@]}" ; do
      declare child_value=${node[$child_key]}

      ent_delete_type $child_value
      unset node[$child_key]
   done

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
