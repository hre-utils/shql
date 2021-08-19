#!/bin/bash

#══════════════════════════════════╡ GLOBAL ╞═══════════════════════════════════
declare -- PROGDIR=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd )
declare -- INFILE="$1"
if [[ ! -e "$INFILE" ]] ; then
   echo "Input file required."
   exit -4
fi

# Source dependencies.
source "${PROGDIR}/config.sh"
source "${PROGDIR}/interpreter.sh"
source "${PROGDIR}/share/lex_functions.sh"
source "${PROGDIR}/share/parse_functions.sh"

declare -- FILE_HASH=$( md5sum "$INFILE" )
declare -- FILE_HASH=${FILE_HASH%% *}

# Location of dumped output from the data compilation.
declare -- PARSEFILE="${PROGDIR}/../.cache/${FILE_HASH}"

if [[ ! -e "$PARSEFILE" ]] ; then
   echo "Input file has not been parsed."
   exit -5
fi

source "$PARSEFILE"

#──────────────────────────────────( lexing )───────────────────────────────────
declare -a TOKENS=()
declare -i GLOBAL_TOKEN_NUMBER=0

declare -a CHARRAY=()
declare -A CURSOR=(
   [lineno]=1
   [colno]=0
   [pos]=-1
)

declare -A FREEZE
# At the beginning of each loop, the cursor information is "frozen", allowing
# us to retain the start position of multi-character tokens (keywords, strings,
# etc.).

declare -- CURRENT PEEK BUFFER
# Global pointer to subsequent tokens, and string buffer to hold the contents
# of multi-character tokens.

# Using an associative array for easier querying.
declare -A KEYWORDS=(
   [len]=true
   [write]=true
   [\print]=true
   [insert]=true
   [update]=true
   [delete]=true
   [append]=true
   [prepend]=true
)

#──────────────────────────────────( parsing )──────────────────────────────────
# Kinda dumb and hacky. Starting at (-1) so the first call to advance() will
# increment by 1, thus reading the *next* character, the first.
declare -i IDX=-1
declare -- TOKEN tPEEK1 tPEEK2
# TOKEN_NAME is the name of the current token.
# TOKEN is a nameref to the token itself.

# AST generation
declare -a REQUEST
declare -- AST_NODE
declare -i GLOBAL_AST_NUMBER=0

# Need to declare a node prefix, as we're re-using the same functions below for
# both the data nodes, and the query nodes. Both of which need unique prefixes
# to stay distinct from each other. When we begin parsing, the $NODE_PREFIX is
# swapped to '_QUERY_NODE_'
declare -- NODE_PREFIX='_QUERY_NODE_'

#═══════════════════════════════════╡ LEXER ╞═══════════════════════════════════
function lex {
   # Fill into array, allows us to seek forwards & backwards.
   while read -rN1 c ; do
      CHARRAY+=( "$c" )
   done <<< "$INPUT_STRING"

   # Iterate over array of characters. Lex into tokens.
   while [[ ${CURSOR[pos]} -lt ${#CHARRAY[@]} ]] ; do
      advance
      [[ -z $CURRENT ]] && break

      # "Freeze" the line number and cursor number, such that they're attached
      # to the *start* of a token, rather than the end.
      FREEZE[lineno]=${CURSOR[lineno]}
      FREEZE[colno]=${CURSOR[colno]}
      FREEZE[pos]=${CURSOR[pos]}

      # Skip comments.
      if [[ "$CURRENT" == '#' ]] ; then
         comment ; continue
      fi

      # Skip whitespace.
      [[ "$CURRENT" =~ [[:space:]] ]] && continue

      # Symbols.
      case "$CURRENT" in
         '.')  Token       'DOT' "$CURRENT" &&  continue ;;
         ';')  Token      'SEMI' "$CURRENT" &&  continue ;;
         ':')  Token     'COLON' "$CURRENT" &&  continue ;;
         ',')  Token     'COMMA' "$CURRENT" &&  continue ;;
         '/')  Token     'SLASH' "$CURRENT" &&  continue ;;
         '>')  Token   'GREATER' "$CURRENT" &&  continue ;;
         '(')  Token   'L_PAREN' "$CURRENT" &&  continue ;;
         ')')  Token   'R_PAREN' "$CURRENT" &&  continue ;;
         '{')  Token   'L_BRACE' "$CURRENT" &&  continue ;;
         '}')  Token   'R_BRACE' "$CURRENT" &&  continue ;;
         '[')  Token 'L_BRACKET' "$CURRENT" &&  continue ;;
         ']')  Token 'R_BRACKET' "$CURRENT" &&  continue ;;
      esac

      # Strings.
      if [[ "$CURRENT" =~ [\"\'] ]] ; then
         string "$CURRENT" ; continue
      fi

      # Identifiers.
      if [[ "$CURRENT" =~ [[:alpha:]_] ]] ; then
         identifier ; continue
      fi

      # Numbers.
      if [[ $CURRENT =~ [[:digit:]] ]] ||
         [[ $CURRENT == '-' && $PEEK == [[:digit:]] ]] ; then
         number ; continue
      fi

      # If none of the above, it's an invalid character.
      local loc="[${FREEZE[lineno]}:${FREEZE[colno]}]"
      Token 'ERROR'  "Syntax Error: $loc Invalid character ${CURRENT@Q}."
   done

   Token 'EOF' 'null'
}

#══════════════════════════════════╡ PARSER ╞═══════════════════════════════════
# Grammar.
#  request     -> transaction (SEMI transaction)* EOF
#  transaction -> query GREATER method
#  query       -> SLASH (index)?
#  index       -> dict_index
#               | list_index
#  dict_index  -> DOT IDENTIFIER
#  list_index  -> '[' INTEGER ']'
#  method      -> insert
#               | update
#               | delete
#               | print
#               | write
#  insert      -> insert '(' STRING|INTEGER COMMA data ')'
#  update      -> update '(' data ')'
#  delete      -> '(' ')'
#  print       -> '(' ')'
#  write       -> '(' string ')'
#  data        -> string
#               | list
#               | dict
#  string      -> '"' non-"-chars '"'
#  list        -> '[' data (COMMA data)* (COMMA)? ']'
#  dict        -> '{' string COLON data (COMMA string COLON data)* (COMMA)? '}'
#
#
# Example created data structure.
#  declare -a REQUEST=(
#     R1
#     R2
#  )
#
#  declare -A R1=(
#     [query]=Q1
#     [method]=M1
#  )
#
#  declare -A Q1=(
#     [type]=list|dict
#     [data]=
#  )
#
#  declare -A M1=(
#     [type]=insert|update|delete|...
#     [data]=A1
#  )
#
#  declare -a A1=(
#     'argument1'
#     'argument2'
#  )

function parse {
   check_lex_errors
   grammar_request
   munch 'EOF'
}

#════════════════════════════════════╡ GO ╞═════════════════════════════════════
read -p 'query> ' INPUT_STRING

lex
parse
interpret

## DEBUG
#declare -p ${!_QUERY_NODE_*}
#declare -p _META
#declare -p _DATA
#declare -p ${!_NODE_*}
