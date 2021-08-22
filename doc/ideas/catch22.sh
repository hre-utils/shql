#═════════════════════════════════╡ SCRIPT 1 ╞══════════════════════════════════
#──────────────────────────────────( wrapper )──────────────────────────────────
#!/bin/bash
# shql.sh
#
# Run either with a filename:
# Or from stdin:                 echo '{"this": "that"}' | ./shql -q '/.this > print()'
#
# Assuming called with the first form:
# ./shql -q '/.this > print()' data.json

declare -- JSON_FILE="data.json"
declare -- QUERY="/.this > print()"

declare -- HASH=$( md5sum $JSON_FILE )
declare -- OUTPUT_FILE="./$HASH"

bash data.sh "$JSON"  "$OUTPUT_FILE"
bash query.sh "$QUERY"  "$OUTPUT_FILE"




#═════════════════════════════════╡ SCRIPT 2 ╞══════════════════════════════════
#─────────────────────────────( json data parser )──────────────────────────────
#!/bin/bash
# data.sh

INPUT_FILE="${1:-/dev/stdin}"
OUTPUT_FILE="${2:-/dev/stdout}"


function lex {
   local text=$( cat $INPUT_FILE )
   # The problem is, we don't have the hash until the data is actually read
   # FROM the file path we passed in...
   declare -g HASH=$( md5sum "$INPUT_FILE" )
   declare -g OUTPUT_FILE="./$HASH"
}

lex ; write_output > "$OUTPUT_FILE"




#═════════════════════════════════╡ SCRIPT 3 ╞══════════════════════════════════
#───────────────────────────────( query parser )────────────────────────────────
#!/bin/bash
# query.sh

QUERY_STRING="$1"
PREVIOUS_OUTPUT="$2"

source $PREVIOUS_OUTPUT

# Do stuff with compiled bash data.




#═══════════════════════════════════╡ IDEAS ╞═══════════════════════════════════
# 1. Export environment variable during data.sh w/ the HASH or OUTPUT_FILE.
#     $ HASH=$( md5sum $JSON_FILE | awk '{print $1}' )
#     $ export OUTPUT_FILE="./$HASH"
#    Can then be used within the query.sh script without explicitly passing as
#    an argument. Though this does lead to some ambiguity if we're getting data
#    from stdin? Could do...
#     $ source ${OUTPUT_FILE:-/dev/stdin}
#    ...though it's a little less explicit than passing directly.
#
# 2. Write the hash to a ~/.cach/hash file
#     $ HASH=$( md5sum $JSON_FILE | awk '{print $1}' )
#     $ touch ./cache/$HASH
#    At the beginning of each run, we'd need to nuke the file so it starts
#    fresh. Can't be left with the file dangling should the user ^C.
#
# 3. Some weird shit with named pipes?
#     $ TMP_CACHE=$(mktemp -u)
#     $ mkfifo $TMP_CACHE
#     $
#     $ HASH=$( md5sum $JSON_FILE | awk '{print $1}' )
#     $ echo "$HASH" > $TMP_CACHE
#    This does allow us to manage the creation of the pipe from `shql` instead
#    of needing to make any changes within `data.sh` or `query.sh`.
#
# 4. Dip caching altogether, pipe output of one to the input of the next. I'm
#    starting to like this solution the more I think about it.
