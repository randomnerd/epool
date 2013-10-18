#!/bin/bash

if [ -z "$1" -o -z "$2" -o -z "$3" ]; then
        echo "  Usage: $0 <host> <port> <password>"
        exit
        fi

pass=$(echo -n "$3" | base64)
msg="{\"id\": 1, \"method\": \"mining.block\", \"params\": [\"$pass\", \"\", \"\"]}"
resp=$(echo "$msg" | nc $1 $2)

