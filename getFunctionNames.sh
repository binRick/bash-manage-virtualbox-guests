#!/bin/bash
cd $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
_F=manager.sh
grep '()' "$_F" |cut -d'(' -f1|sed 's/[[:space:]]//g'
