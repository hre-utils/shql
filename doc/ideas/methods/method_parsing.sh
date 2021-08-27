#!/bin/bash
# method_parsing.sh
#
# Should compile methods down a little bit more. Hold off on evaluating the
# content of the arguments until after parsing the structure of the general
# query itself.
#
# This allows us to
#  1. Produce better & more accurate error output
#  2. Handle a greater number of error before halting execution
#
# Currently we're mixing interpretation & node generation the same phase. This
# would separate those out more.

#───────────────────────────────────( given )───────────────────────────────────
declare -- json='
{
   "this": [
      "one",
      "two",
      "three",
   ]
}
'

declare -- query='/.this > insert(1, ["one", "two"])'


#───────────────────────────────( data: parsed )────────────────────────────────
declare -A _DATA=(
   [ROOT]='N1'
)
declare -A N1=(
   [this]=N2
)
declare -a N2=(
   'N3'
   'N4'
   'N5'
)
declare -- N3='one'
declare -- N4='two'
declare -- N5='three'


#───────────────────────────────( query: parsed )───────────────────────────────
declare -A Q1=(            # Statement
   [location]='Q2'
   [method]='Q3'
)
declare -a Q2=(            # LocationList()
   'Q4'
   'Q5'
)
declare -A Q3=(            # Method()
   [type]='insert'
   [arglist]='Q6'
)
declare -A Q4=(            # Location()
   [type]='dict'
   [data]='ROOT'
)
declare -A Q5=(            # Location()
   [type]='dict'
   [data]='this'
)
declare -a Q6=(            # Arglist()
   'Q7'
   'Q8'
)
declare -i Q7=(            # Integer()
)
declare -a Q8=(            # Data()
)

# Hmm, this brings us to a good point... do we want to actually parse these
# nodes here now? Or just append everything until the closing ')' to the
# arglist? No. Arglist should be separated into arguments.
_='... update(1, ["one", "two"])'
# Should evaluate to

declare -a ARGLIST=(       # Arglist()
   'A1'
   'A2'
)
declare -A A1=(            # Argument()
   [type]='POSITIONAL'
   [data]='A3'
)
declare -A A2=(            # Argument()
   [type]='POSITIONAL'
   [data]='A4'
)
declare -A A3=(            # NodeList()
   'A5'
)
declare -A A5=(            # Data()
   [type]='INTEGER'
   [data]=1
)
declare -a A4=(            # NodeList()
   'A6'
   'A7'
   'A8'
   'A9'
   'A10'
)
declare -A A6=(            # Data()
   [type]='L_BRACKET'
   [data]='['
)
declare -A A7=(            # Data()
   [type]='STRING'
   [data]='one'
)
declare -A A8=(            # Data()
   [type]='COMMA'
   [data]=','
)
declare -A A9=(            # Data()
   [type]='STRING'
   [data]='two'
)
declare -A A10=(           # Data()
   [type]='R_BRACKET'
   [data]=']'
)

#────────────────────────────────( call method )────────────────────────────────
# Then after we've parsed to this point above, we can parse the argument list
# into a second arglist that's passed to the method itself.
declare -a METHODLIST=(
   'A11'
   'A12'
)
declare -i A11=1           # Arg1: 1
declare -a A12=(           # Arg2: ['one', 'two']
   'A13'
   'A14'
)
declare -- A13='one'
declare -- A14='two'

case ${method[type]} in
   # ...
   'insert')  method_insert 'METHODLIST' 
   # ...
esac

function method_insert {
   declare -n methodlist=$1
   if [[ ${#methodlist[@]} -gt 2 ]] ; then
      raise_argument_error "${method[type]}()" "2" "${#methodlist[@]}"
      # Argument Error: Method 'insert()' takes '2' arguments, 'N' were given.
   fi

   declare -n index=${methodlist[0]}
   declare -n data=${methodlist[1]}

   if [[ ! ${index[type]} =~ (STRING|INTEGER) ]] ; then
      raise_type_error "${method[type]}" 'STRING,INT' "${index[type]}"
   fi

   # etc.
}

# May even want to separate the validation from the method call itself. Given
# the overall complexity of this utility, an added level of abstraction to
# remove the validation from the method call may make it easier to understand
# what's happening.

