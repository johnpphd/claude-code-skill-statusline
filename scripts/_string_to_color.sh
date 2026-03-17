#!/usr/bin/env bash
# Port of maverick stringToColor (triple-hash djb2 -> hex -> 256-color ANSI).
# Source this from statusline.sh.
#
# Exports:
#   _project_color256 "string" -> prints a 256-color index (16-231)

_string_to_color_hash() {
  local str
  str=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  local hash=0
  local i char_code

  for (( i=0; i<${#str}; i++ )); do
    char_code=$(printf '%d' "'${str:$i:1}")
    hash=$(( char_code + ((hash << 5) - hash) ))
    # Keep within 32-bit signed range to match JS behavior
    hash=$(( hash & 0xFFFFFFFF ))
    # Sign-extend to match JS signed 32-bit
    if (( hash > 0x7FFFFFFF )); then
      hash=$(( hash - 0x100000000 ))
    fi
  done

  local colour="#"
  local val hex
  for (( i=0; i<3; i++ )); do
    val=$(( (hash >> (i * 8)) & 0xFF ))
    hex=$(printf '%02x' "$val")
    colour="${colour}${hex}"
  done
  echo "$colour"
}

_string_to_color() {
  # Triple-hash: apply stringToColorHash three times
  local result
  result=$(_string_to_color_hash "$1")
  result=$(_string_to_color_hash "$result")
  result=$(_string_to_color_hash "$result")
  echo "$result"
}

_project_color256() {
  local hex
  hex=$(_string_to_color "$1")
  # Strip '#' and parse RGB
  hex="${hex#\#}"
  local r=$(( 16#${hex:0:2} ))
  local g=$(( 16#${hex:2:2} ))
  local b=$(( 16#${hex:4:2} ))

  # Clamp brightness: if luminance is too high, scale down
  # Relative luminance (approximate): 0.299*R + 0.587*G + 0.114*B
  local lum=$(( (299 * r + 587 * g + 114 * b) / 1000 ))
  if (( lum > 180 )); then
    # Scale down proportionally
    r=$(( r * 140 / lum ))
    g=$(( g * 140 / lum ))
    b=$(( b * 140 / lum ))
  elif (( lum < 40 )); then
    # Boost dim colors so the block is visible
    local boost=$(( 60 - lum + 1 ))
    r=$(( r + boost > 255 ? 255 : r + boost ))
    g=$(( g + boost > 255 ? 255 : g + boost ))
    b=$(( b + boost > 255 ? 255 : b + boost ))
  fi

  # Map to 6x6x6 color cube (indices 16-231)
  # Each axis: 0-255 -> 0-5, rounding to nearest
  local ri=$(( (r + 25) / 51 ))
  local gi=$(( (g + 25) / 51 ))
  local bi=$(( (b + 25) / 51 ))
  # Clamp to 0-5
  (( ri > 5 )) && ri=5
  (( gi > 5 )) && gi=5
  (( bi > 5 )) && bi=5

  echo $(( 16 + 36 * ri + 6 * gi + bi ))
}
