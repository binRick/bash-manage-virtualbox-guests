#!/bin/bash
command iptables -I INPUT -i wg0 -s 10.14.0.2 -j ACCEPT
command iptables -I INPUT -i wg0 -s 10.14.0.1 -j ACCEPT
