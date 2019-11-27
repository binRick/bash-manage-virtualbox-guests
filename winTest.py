#!/usr/bin/env python3
import os, json, sys, winrm, base64
u = 'User'
p = os.environ['WINPASS']
h = 'http://127.0.0.1:5985/wsman'

p = winrm.protocol.Protocol(
        endpoint=h,
        transport='ntlm',
        username=u,
        password=p,
        server_cert_validation='ignore')

shell_id = p.open_shell()
command_id = p.run_command(shell_id, 'ipconfig', ['/all'])
std_out, std_err, status_code = p.get_command_output(shell_id, command_id)
p.cleanup_command(shell_id, command_id)
p.close_shell(shell_id)

print(std_out.decode())
print(std_err.decode())
print(status_code)
