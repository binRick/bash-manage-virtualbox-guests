#!/bin/bash
bash +x ./manager.sh $@ 2>/dev/null || bash -x ./manager.sh $@
