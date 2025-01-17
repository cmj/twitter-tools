#!/bin/bash

id=$1

media_key=$(./AudioSpaceById.sh "${id##*/}" | jq -r .data.audioSpace.metadata.media_key)

./spaces.sh "${media_key}"

