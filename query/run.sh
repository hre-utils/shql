#!/bin/bash

declare -g PROGDIR=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd )

#══════════════════════════════════╡ GLOBAL ╞═══════════════════════════════════
# Color garbage.
rst=$(tput sgr0)                                   # Reset
bk="$(tput setaf 0)"                               # Black
rd="$(tput setaf 1)"  ;  brd="$(tput bold)${rd}"   # Red     ;  Bright Red
gr="$(tput setaf 2)"  ;  bgr="$(tput bold)${gr}"   # Green   ;  Bright Green
yl="$(tput setaf 3)"  ;  byl="$(tput bold)${yl}"   # Yellow  ;  Bright Yellow
bl="$(tput setaf 4)"  ;  bbl="$(tput bold)${bl}"   # Blue    ;  Bright Blue
mg="$(tput setaf 5)"  ;  bmg="$(tput bold)${mg}"   # Magenta ;  Bright Magenta
cy="$(tput setaf 6)"  ;  bcy="$(tput bold)${cy}"   # Cyan    ;  Bright Cyan
wh="$(tput setaf 7)"  ;  bwh="$(tput bold)${wh}"   # White   ;  Bright White

declare -A colormap=(
   [DOT]="$yl"
   [COLON]="$wh"
   [COMMA]="$wh"
   [STRING]="$rd"
   [NUMBER]="$bl"
   [COMMENT]="$cy"
   [KEYWORD]="$yl"
   [L_PAREN]="$wh"
   [R_PAREN]="$wh"
   [L_BRACE]="$wh"
   [R_BRACE]="$wh"
   [L_BRACKET]="$wh"
   [R_BRACKET]="$wh"
   [IDENTIFIER]="$bcy"
   [EOF]="$gr"
)

#────────────────────────────────────( go )─────────────────────────────────────
source "${PROGDIR}/lib/lexer.sh"
read -p 'query> ' INPUT_STRING

lex
print_tokens