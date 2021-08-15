# vim:ft=bash
#
# Takeaways after talking things through with my dad. Two potential approaches:
#  1. Change the "root" node to look like this:
#           declare -A ROOT=(
#              [ROOT]=(
#              )
#           )
#     Instead of $ROOT being a pointer to the root node, it can be a real node
#     per se, as the other nodes are. It's not some sort of magic, special type
#     of node. This is exacty what I was setting out to do, I just couldn't
#     concieve of how.
#  2. Create extra keys in dictionary nodes (and *only* in dictionaries), that
#     refer back to their parents. It's unnecessary within a list. Think about
#     it and draft out some examples for proof. Study the sample again below.
#     This approach can also replace the stack, though it feels a little less
#     "elegant" to me.


#═══════════════════════════════╡ DATA PARSING ╞════════════════════════════════
#────────────────────────────( step 1: input json )─────────────────────────────
input='
ROOT={
   "ROOT": {
      "foo": {
         "bar": "baz"
      },
      "list": [
         "one"
         "two"
      ]
   }
}
'

# TAKE OUT THE MAGIC--add an additional level, with a key as ROOT to refer to
# the root node, not a variable.

#──────────────────────────( step 2: compiled nodes )───────────────────────────
# associative array.
declare -A ROOT=(
   [ROOT]=N1
)

# associative array.
declare -A N1=(
   [foo]='N2'
   [list]='N4'
   #[\$parent]='ROOT'
   #[\$key]='ROOT'
   # I don't really like this approach as much as maintaining a stack, however
   # there is something quite interesting about it as well.
)


# associative array.
declare -A N2=(
   [bar]='N3'
   #[\$parent]='N1'
   #[\$key]='foo'
)

# string.
declare -- N3='baz'

# list.
declare -a N4=(
   'N5'
   'N6'
)

# strings.
declare -- N5='one'
declare -- N6='two'

#═══════════════════════════════╡ QUERY PARSING ╞═══════════════════════════════
#────────────────────────( step 1: input query string )─────────────────────────
query=' /.list > print() '

#──────────────────────────( step 3: compiled query )───────────────────────────
# "Parts" are effectively:
#   1.  '/'       identifies root node
#   2.  '.foo'    dict subscription of previous node w/ key 'foo'

# change to "dict index" and "list index"

declare -a FULL_QUERY=(
   'Q1'
   'Q2'
  #'Q3'
)

declare -A Q1=(
   [\type]='dict'
   [data]='ROOT'
)

declare -A Q2=(
   [\type]='dict'
   [data]='list'
)

#declare -A Q3=(
#   [\type]='list'
#   [data]='0'
#)

#declare -a FULL_QUERY=(
#   'Q1'
#)
#
#declare -A Q1=(
#   [\type]='dict'
#   [data]='ROOT'
#)

#─────────────────────────────( step 3: traverse )──────────────────────────────
# Traverse json nodes to find the 'target' node, check along the way that the
# user's query is valid.

# Create stack to refer back to parent nodes.
declare -a stack=()

# Initial node:
DATA_NODE=ROOT

# Iterate over query to check if valid, find target node.
for query_node in "${FULL_QUERY[@]}" ; do
   declare -n query=$query_node
   declare -n node=$DATA_NODE

   stack+=( $DATA_NODE )
   
   key=${query[data]}
   next=${node[$key]}

   if [[ -z $next ]] ; then
      echo "stack[ ${stack[@]} ]"
      echo "Invalid Query: ${DATA_NODE}[${parent[$key]}]"
      exit 1
   fi

   DATA_NODE=$next
done


#═══════════════════════════════╡ PRETTY PRINT ╞════════════════════════════════
function pretty_print {
   local t=$( declare -p $1 | awk '{print $2}' )

   case $t in
      '--')    print_string $1 ;;
      '-a')    print_list   $1 ;;
      '-A')    print_dict   $1 ;;
   esac
}


function print_string {
   declare -n node=$1
   echo "'$node'"
}


function print_list {
   # Save local reference to previous global DATA_NODE, then set current global
   # to this node.
   local data_node=$DATA_NODE
   DATA_NODE=$1

   ((INDENTATION++))
   echo "["

   declare -n node=$1
   for child in "${node[@]}" ; do
      indent ; pretty_print $child
   done

   ((INDENTATION--))
   indent ; echo "]"

   # Restore previous global value.
   DATA_NODE=$data_node
}


function print_dict {
   # Save local reference to previous global DATA_NODE, then set current global
   # to this node.
   local data_node=$DATA_NODE
   DATA_NODE=$1

   ((INDENTATION++))
   echo "{"

   declare -n node=$1
   for key_string in "${!node[@]}" ; do
      child=${node[$key_string]}
      indent ; echo "'${key_string}': $(pretty_print $child)"
   done

   ((INDENTATION--))
   indent ; echo "}"

   # Restore previous global value.
   DATA_NODE=$data_node
}


declare -i INDENTATION=0

function indent {
   printf "%$(( INDENTATION * 2 ))s" ''
}


#══════════════════════════════════╡ DELETE ╞═══════════════════════════════════
function delete {
   local t=$( declare -p $1 | awk '{print $2}' )

   case $t in
      '--')       delete_string $1 ;;
      '-a'|'-A')  delete_array  $1 ;;
   esac
}


# Bash array subscription is identical to dict subscription. No need for two
# methods.
function delete_array {
   local query=$QUERY
   declare -- node_name=$1
   declare -n node=$node_name

   DATA_NODE=$node_name
   stack+=( $DATA_NODE )

   for key in "${!node[@]}" ; do
      QUERY=$key                                # Set global query string
      delete ${node[$key]}                      # Kick off recursive child deletion
      unset node[$key]                          # Unset element from array
   done

   declare -n parent=${stack[-1]}               # Refernce parent element on stack
   unset parent[$query]                         # Unset this element from its parent
   unset $node_name                             # Unset self.

   QUERY=$query
}


function delete_string {
   unset $1                                     # Unset self.

   declare -n parent=${stack[-1]}               # Nameref to parent's node
   unset parent[$query]                         # Unset reference from parent
   unset stack[-1]
}

declare -- query=${FULL_QUERY[-1]}
declare -n query
declare -g QUERY=${query[data]}

pretty_print ${ROOT[ROOT]}
delete N4

echo
pretty_print ${ROOT[ROOT]}

for i in $(seq 1 6) ; do
   declare -p "N${i}" 2>/dev/null
done
