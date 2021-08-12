#!/bin/bash

# Initial node
NODE_NAME=$_ROOT
NODE_PREV=$_ROOT

LOCATION_LIST=    # This transactions location list.
LOCATION=$_ROOT   # Current location within the list.
METHOD=

# CURRENT
# Struggling on a good method to delete the children of an object, but also the
# reference to it from it's parent. We need to hang onto the path to our current
# location, as well as the references to get there.
# Maybe setting a CURRENT_PATH[], then in `intr_get_location()` append the route
# taken. Will need to come up with a better way to handle the _ROOT node though.
# I think.
#
# Try to write a new function that uses this approach.

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
   for transaction_node_name in "${TRANSACTION[@]}" ; do
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
   declare -n location=$LOCATION_LIST

   for loc_name in "${location[@]}" ; do
      declare -n loc=$loc_name
      declare -n node=$NODE_NAME

      # Tracking the current location within the AST. This allows us to refer
      # from the parent to this node.
      LOCATION=$loc_name
      NODE_PREV=$NODE_NAME

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
   ent_delete
   #print_data_type $_ROOT ##DEBUG
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
   declare -n n=$NODE_NAME
   echo "Beginning deletion of $NODE_NAME"

   ent_delete_type "$NODE_NAME"
   ent_delete_from_parent
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


function ent_delete_from_parent {
   local child_loc_name=$LOCATION
   declare -n child_loc=$child_loc_name

   local parent_name=$NODE_PREV
   declare -n parent=$parent_name
   parent_type=$( get_type $parent_name )

   if [[ $parent_name == $_ROOT ]] ; then
      unset $parent_name
      _ROOT=''
   else
      unset parent[${child_loc[data]}]
   fi
}


function ent_delete_type_string {
   declare -n n=$1
   echo "Unsetting $n"
   unset $1
}


function ent_delete_type_list {
   declare node_name="$1"
   declare -n node="$node_name"

   for idx in "${!node[@]}" ; do
      ent_delete_type ${node[$idx]}
   done
}


function ent_delete_type_dict {
   declare node_name="$1"
   declare -n node="$node_name"

   for child_key in "${!node[@]}" ; do
      declare child_value=${node[$child_key]}
      ent_delete_type $child_value
   done
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
