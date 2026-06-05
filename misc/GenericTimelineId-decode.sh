#!/usr/bin/env bash
# Decode base64 string used in GenericTimelineById
# ex: VGltZWxpbmU6CgCeHKDgKS2W0A8A

b64=$1

if [[ -z "$b64" ]]; then echo "usage: $0 BASE64_STRING"; exit 1; fi

hex=$(printf '%s' "$b64" | base64 -d 2>/dev/null | od -An -tx1 | tr -d ' \n')

nul=${hex%%00*}
label=$(printf '%s00' "$nul" | xxd -r -p | tr -d '\0\n')

tail=${hex:$(( ${#nul} + 2 ))}
snowflake=$((16#${tail:2:16}))

printf '%s %s\n' "$label" "$snowflake"
