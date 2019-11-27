#!/usr/bin/env python3
import os, json, sys, winrm, base64
p = os.environ['WINUSER']
p = os.environ['WINPASS']
if 'WINURI' in os.environ:
    h = os.environ['WINURI']
else:
    h = 'http://127.0.0.1:5985/wsman'


ps_script = """$strComputer = $Host
Clear
$RAM = WmiObject Win32_ComputerSystem
$MB = 1048576

"Installed Memory: " + [int]($RAM.TotalPhysicalMemory /$MB) + " MB" """



#s = winrm.Session(h, auth=(u,p))
#r = s.run_ps(ps_script)

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
