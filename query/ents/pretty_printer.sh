#!/bin/bash

function pretty_print {
   echo "LOCATIONS:"
   for loc_name in "${LOCATION[@]}" ; do
      declare -n loc=$loc_name
      echo -n "${loc[data]} -> "
   done
   echo

   print_data_type "${METHOD[data]}"
}


function indent {
   printf -- "%$(( INDNT_LVL * INDNT_SPS ))s"  ''
}


function print_data_type {
   declare node_name="$1"
   declare node_type=$( get_type "$node_name" )

   case $node_type in
      'string')   pp_string "$node_name" ;;
      'list')     pp_list   "$node_name" ;;
      'dict')     pp_dict   "$node_name" ;;
   esac
}


function get_type {
   declare t=$(declare -p "$1" | awk '{print $2}')

   case $t in
      '--')    echo 'string' ;;
      '-a')    echo 'list'   ;;
      '-A')    echo 'dict'   ;;
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
