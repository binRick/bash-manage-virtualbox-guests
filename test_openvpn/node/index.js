#!/usr/bin/env node

var os = require('os'),
    l = console.log,
    pty = require('node-pty'),
    c = require('chalk'),
    async = require('async'),
        _ = require('underscore'),
        fs = require('fs'),
        nunjucks = require('nunjucks'),
        validateip = require('validate-ip'),
        shell = os.platform() === 'win32' ? 'powershell.exe' : 'bash';

const handleShutdown = (e, n) => {
    console.log(c.yellow('>>>HANDLING SHUTDOWN'), e, n);
    process.exit(e);
};
//process.on('exit', handleShutdown);
//process.on('SIGINT', handleShutdown);

var VIRTUALBOX_COMMAND_TEMPLATE = "command VBoxManage guestcontrol {{vm}} --username root --password {{password}} run --exe /bin/bash --wait-stdout --timeout {{timeout}} -- bash/arg0 -c",
    OPENVPN_CLIENT_CMD_TEMPLATE = "killall openvpn 2>/dev/null; cd /root && command openvpn --version 2>/dev/null; command openvpn {{config}}",
    CURL_CMD_TEMPLATE = 'command curl --resolve ifconfig.me:80:216.239.32.21 -4 -s ifconfig.me',
    PS_CMD_TEMPLATE = 'command ps axfuw',
    genCommand = function(CMD_TEMPLATE, VM, PASSWORD, TIMEOUT, CONFIG) {
        var TEMPLATE = VIRTUALBOX_COMMAND_TEMPLATE + " '" + CMD_TEMPLATE + "'";
        var command = nunjucks.renderString(TEMPLATE, {
            vm: VM,
            password: PASSWORD,
            timeout: TIMEOUT,
            config: CONFIG
        });
        return command;
    };


var getCommandOutput = function(cmd, WRITE_EXIT, _cb, __cb) {
    var cmdProc = pty.spawn(shell, [], {
        name: 'xterm-256color',
        cols: 80,
        rows: 30,
        cwd: process.env.HOME,
        env: process.env
    });
    var killFxn = function() {
        cmdProc.kill();
    };
    cmdProc.started_ts = Date.now();
    var D = '';
    cmdProc.on('data', function(data) {
        __cb(data.toString(), killFxn);
        D += data.toString();
    });
    cmdProc.onExit(function(code) {
        clearInterval(cmdInterval);
        cmdProc.ended_ts = Date.now();
        var duration_ms = cmdProc.ended_ts - cmdProc.started_ts;
        //l('cmd', cmd, 'finished with code', code, 'and', D.length, 'bytes of output after', duration_ms, 'ms');
        _cb({
            code: code,
            stdout: D,
        });
    });
    cmdProc.write(cmd + '\r');
    if (WRITE_EXIT)
        setTimeout(function() {
            cmdProc.write('exit\r');
        }, 1000);
    var cmdInterval = setInterval(function() {
        //l('Checking pid', cmdProc.pid);
    }, 1000);
};


/*
var cmd = genCommand(PS_CMD_TEMPLATE, 'centos-8-vm232', process.env['_PASS'], 30000, 'config.ovpn');
getCommandOutput(cmd, function(output) {
    output.stdout = output.stdout.split("\n");
    l('stdout>', output.stdout);
    l('code>', output.code);
});
l('done');
*/





var OPENVPN_CLIENT_CONNECT_CMD = genCommand(OPENVPN_CLIENT_CMD_TEMPLATE, 'centos-8-vm232', process.env['_PASS'], 30000, 'config.ovpn');
var CURL_CMD = genCommand(CURL_CMD_TEMPLATE, 'centos-8-vm232', process.env['_PASS'], 30000, 'config.ovpn');

l(c.white('OPENVPN_CLIENT_CONNECT_CMD: ') + ' ' + c.green(OPENVPN_CLIENT_CONNECT_CMD));
l(c.white('CURL_CMD: ') + ' ' + c.green(CURL_CMD));

var openvpnClientProcess = pty.spawn(shell, [], {
    name: 'xterm-256color',
    cols: 80,
    rows: 30,
    cwd: process.env.HOME,
    env: process.env
});
openvpnClientProcess.started_ts = Date.now();

var startCurlProcess = function() {
    l(c.yellow('Starting Curl', CURL_CMD));
    getCommandOutput(CURL_CMD, false, function(output) {
        output.stdout = output.stdout.split("\n");
        l('curl stdout>', output.stdout);
        l('curl code>', output.code);
    }, function(realtimeOutput, _kill_cb) {
        _.each(realtimeOutput.split("\n"), function(line) {
            line = line.trim();
            if (validateip(line)) {
                l(c.yellow('\n\n                  DETECTED VALID IP FROM CURL: ' + line + '\n\n'));
                _kill_cb();
            }
        });

    });
}


openvpnClientProcess.on('exit', function(code) {
    openvpnClientProcess.ended_ts = Date.now();
    var duration = openvpnClientProcess.ended_ts - openvpnClientProcess.started_ts;
    var duration2 = openvpnClientProcess.ended_ts - openvpnClientProcess.connected_ts;
    l(c.green('\n\n                  OPENVPN CLIENT EXITED AFTER ' + duration + 'ms of execution and ' + duration2 + 'ms of openvpn connection\n\n'));

});

var OUTPUT = '';
openvpnClientProcess.on('data', function(data) {
    OUTPUT += data;
    //       process.stdout.write(data);
    if (data.startsWith('OpenVPN')) {
        var version = data.split("\n")[0].split(" ")[1];
        l(c.green('\n\n                  DETECTED OPENVPN VERSION ' + version + '\n\n'));
        clearTimeout(failedOpenVpnTimeout);

    }
    if (data.includes('Initialization Sequence Completed')) {
        openvpnClientProcess.connected_ts = Date.now();
        var duration = openvpnClientProcess.connected_ts - openvpnClientProcess.started_ts;
        l(c.green('\n\n                  VPN IS ACTIVE AFTER ' + duration + 'ms\n\n'));
        startCurlProcess();
    }
});

openvpnClientProcess.write(OPENVPN_CLIENT_CONNECT_CMD + '\r');
setTimeout(function() {
    openvpnClientProcess.write('exit\r');
}, 500);

var failedOpenVpnTimeout = setTimeout(function() {
    l(c.red('Openvpn seems to have failed. checking........'));
}, 10000);
