#!/bin/bash

#═══════════════════════════════════╡ GIVEN ╞═══════════════════════════════════
# Given the following 'compiled' data source...

declare -- ROOT=N1
declare -A N1=([foo]=N2)
declare -- N2='bar'


#═════════════════════════════════╡ THINKIES ╞══════════════════════════════════
# What if we designed some sort of... NavigationNodes.
# They would define the navigation path, and give the necessary information to
# re-navigate, w/ the queries. Wonder if we can do a 'functional' approach, in
# which the properties are the name of the function to call, and a pointer to
# a list of the arguments to pass to it. Example:

#     declare -a NAVIGATION_NODES=(
#        _NAV_1
#        _NAV_2
#        _NAV_3
#     )
#     
#     declare -A _NAV_1=(
#        [\function]='nav_basic'    # Basic key-> value nav.
#        [arguments]=_NAV_5
#     )
#     declare -a _NAV_5=( '_ROOT')
#     
#     declare -A _NAV_2=(
#        [\function]='nav_sub'      # Array subscription nav.
#        [arguments]=_NAV_6
#     )
#     declare -a _NAV_6=(
#        'N1'
#        'this'
#     )
#     
#     
#     function nav_basic {
#        declare -n node=$1
#        echo $node
#     }
#     
#     
#     function nav_sub {
#        declare -n node=$1
#        declare -- key=$2
#     
#        echo "${node[$key]}"
#     }
#     
#     
#     function traverse {
#        for nav_node in "${NAVIGATION_NODES[@]}" ; do
#           declare -n nav=$nav_node
#     
#           next=$( ${nav[function]} ${nav[arguments]} )
#        done
#     }


#═══════════════════════════════════╡ PARSE ╞═══════════════════════════════════
declare -- QUERY=
declare -a stack=()
declare -a key_stack=

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

   #if [[ -z $QUERY ]] ; then
   #   declare -n node=ROOT
   #   node=''
   #else
   #   declare -n node=${stack[-1]}
   #   unset node[$QUERY]
   #fi

   declare -n node=${stack[-1]}
   unset node[$QUERY]

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

   #if [[ -z $query ]] ; then
   #   declare -n node=ROOT
   #   unset $node
   #   node=''
   #else
   #   declare -n node=${stack[-1]}
   #   unset node[$query]
   #fi

   unset stack[-1]
   QUERY=$query
}


#node_name=ROOT
#stack+=( $node_name )
#
#declare -n node=$node_name
#delete_by_type $node

stack=( ROOT N1 )
delete_by_type N2

echo -e "\nstack[ ${stack[@]} ]\n"
for var in ROOT N1 N2 ; do
   declare -p $var 2>/dev/null
done
echo
