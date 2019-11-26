#!/bin/bash
cd $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
nodemon -w . -e sh,py,json,yaml -x ./dev.sh -- $@
