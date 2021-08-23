#!/bin/bash
# Compilation & parsing of input .json data

#══════════════════════════════════╡ GLOBAL ╞═══════════════════════════════════
declare -- JSON_FILE="${1:-/dev/stdin}"
declare -- JSON_DATA

# Source dependencies.
# SHQL_ROOT is exported in the `shql` script. It is expected to be set to the
# root of the install location (e.g., /usr/local).
source "${SHQL_ROOT}/lib/shql/lex_functions.sh"
source "${SHQL_ROOT}/lib/shql/parse_functions.sh"
source "${SHQL_ROOT}/share/shql/config.sh"

# For printing better error output.
declare -a FILE_BY_LINES

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

#──────────────────────────────────( parsing )──────────────────────────────────
# Kinda dumb and hacky. Starting at (-1) so the first call to advance() will
# increment by 1, thus reading the *next* character, the first.
declare -i IDX=-1
declare -- TOKEN tPEEK1 tPEEK2
# TOKEN is a nameref to the token itself.

# AST generation
declare -- AST_NODE
declare -i GLOBAL_AST_NUMBER=0
# For unique naming. Each node is named "NODE_${GLOBAL_AST_NUMBER}", then
# incremented. Hashes are for dummies.

declare -A _DATA=(
   [ROOT]=
)
# By shifting the root of the data structure to be a value under this "ROOT"
# associative array, it allows us to treat the root node indistinguishably from
# any other node. See more extensive notes in [4c40211 query/thinkies/flow.sh].

declare -A _META
# For tracking meta information that's written to the cachefile. Currently it
# only contains the end result of the GLOBAL_AST_NUMBER. This allows us to, in
# the event of insertions in the 'query' phase, pick up where these tokens left
# off.

# Need to declare a node prefix, as we're re-using the same functions below for
# both the data nodes, and the query nodes. Both of which need unique prefixes
# to stay distinct from each other. When we begin parsing, the $NODE_PREFIX is
# swapped to '_QUERY_NODE_'
declare -- NODE_PREFIX='_NODE_'

#═══════════════════════════════════╡ LEXER ╞═══════════════════════════════════
function lex {
   # So we don't need to read from the file twice.
   JSON_DATA=$( cat "$JSON_FILE" )

   # Fill individual characters into array, allows more easy 'peek' operations.
   while read -rN1 c ; do
      CHARRAY+=( "$c" )
   done <<< "$JSON_DATA"

   # Creating secondary line buffer to do better debug output printing. It would
   # be more efficient to *only* hold a buffer of lines up until each newline.
   # Unpon an error, we'd only need to save the singular line, then can resume
   # overwriting. This is in TODO already.
   mapfile -td $'\n' FILE_BY_LINES <<< "$JSON_DATA"

   while [[ ${CURSOR[pos]} -lt ${#CHARRAY[@]} ]] ; do
      advance
      [[ -z $CURRENT ]] && break

      # See detail in the 'GLOBAL' section concerning FREEZE.
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
         ':')  Token     'COLON' "$CURRENT" &&  continue ;;
         ',')  Token     'COMMA' "$CURRENT" &&  continue ;;
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
# grammar:
#     root -> dict EOF
#           | list EOF
#     list -> '[' data (COMMA data)* (COMMA)? ']'
#     dict -> '{' string COLON data (COMMA string COLON data)* (COMMA)? '}'
#     data -> dict
#           | list
#           | STRING
#           | NUMBER

# The vast majority of the parser is not unique to either the data section, or
# the query section. All of the functions have been combined in lib/share/
function parse {
   check_lex_errors

   grammar_root
   _DATA[ROOT]=$AST_NODE

   munch 'EOF'
}


function dump_nodes {
   (
      _META[max_node_ref]=$GLOBAL_AST_NUMBER
      declare -p _META
      declare -p _DATA
      if [[ -n ${!_NODE_*} ]] ; then
         declare -p ${!_NODE_*}
      fi
   ) | sort -V -k3
}

#════════════════════════════════════╡ GO ╞═════════════════════════════════════
# Compile.
lex
parse
dump_nodes
