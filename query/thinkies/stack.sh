#!/bin/bash

#═══════════════════════════════════╡ GIVEN ╞═══════════════════════════════════
# Given the following 'compiled' data source...

declare -- ROOT=N1
declare -A N1=([foo]=N2)
declare -- N2='bar'


#═══════════════════════════════════╡ PARSE ╞═══════════════════════════════════
declare -- QUERY=
declare -a stack=()

function delete_by_type {
   local type=$( get_type $1 )

   case $type in
      string)     delete_str $1 ;;
      list|dict)  delete_arr $1 ;;
   esac
}


function get_type {
   local t=$(declare -p "$1" | awk '{print $2}')

   case $t in
      '--')    echo 'string' ;;
      '-a')    echo 'list'   ;;
      '-A')    echo 'dict'   ;;
   esac
}


function delete_str {
   unset $1

   if [[ -z $QUERY ]] ; then
      declare -n node=ROOT
      node=''
   else
      declare -n node=${stack[-1]}
      unset node[$QUERY]
   fi

   unset stack[-1]
}


function delete_arr {
   local query=$QUERY
   declare -- node_name=$1
   declare -n node=$node_name

   stack+=( $node_name )

   for key in "${!node[@]}" ; do
      QUERY="$key"
      child_name=${node[$key]}

      delete_by_type $child_name
      unset node[$key]
   done

   if [[ -z $query ]] ; then
      declare -n node=ROOT
      unset $node
   else
      declare -n node=${stack[-1]}
      unset node[$query]
   fi

   unset stack[-1]
   QUERY=$query
}


node_name=ROOT
stack+=( $node_name )

while [[ ${#stack[@]} -gt 0 ]] ; do
   declare -n node=$node_name
   stack+=( $child )
   delete_by_type $node
done

for var in ROOT N1 N2 ; do
   declare -p $var 2>/dev/null
done
