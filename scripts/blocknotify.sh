#!/bin/bash

if [ -z "$1" -o -z "$2" -o -z "$3" ]; then
        echo "  Usage: $0 <host> <port> <password>"
        exit
        fi

pass=$(echo -n "$3" | shasum -a 256 | cut -f1 -d' ')
msg="{\"id\": 1, \"method\": \"mining.update_block\", \"params\": [\"$pass\"]}"
resp=$(echo "$msg" | nc $1 $2)
echo $msg
echo $resp

