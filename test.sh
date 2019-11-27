#!/usr/bin/env bash
time seq 100 110 | xargs -I % time sh -c './manager.sh vm%'
