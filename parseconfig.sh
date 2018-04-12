#!/bin/bash

FILE=$1

if [ "$FILE" = "" ] || [ ! -f $FILE ]; then
	echo "FILE of [$FILE] not exit"
	exit 1
fi

sed '/^\s*$/d' -i $FILE
sed '/^#/d' -i $FILE
sed '/^\t#/d' -i $FILE
sed '/^\t\t#/d' -i $FILE
sed '/^\t\t\t#/d' -i $FILE
