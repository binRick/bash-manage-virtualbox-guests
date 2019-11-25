#!/usr/bin/env bash
set -e -o pipefail
cd $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

. .bash-concurrent/concurrent.lib.sh
set +e
command yaml2json --version >/dev/null 2>&1 || . ~/.venv/bin/activate
set -e

TEMPLATE_BASE=centos-8-
TEMPLATE_KEYWORD=template
NEW_VM=${TEMPLATE_BASE}$1
NEW_HOSTNAME=$NEW_VM
TEMPLATE=${TEMPLATE_BASE}${TEMPLATE_KEYWORD}
SNAPSHOT_NAME=${TEMPLATE_KEYWORD}-snapshot
PUBLIC_KEY_FILE=~/.ssh/id_rsa.pub
[[ "$PASS" == "" ]] && export PASS=12341234
COMMON_ARGS="--username root --password $PASS"

snapshotVM(){
       TEMPLATE="$1"
       SNAPSHOT_NAME="$2"
	VBoxManage snapshot $TEMPLATE list|grep "Name: $SNAPSHOT_NAME (UUID: " >/dev/null || 
	  VBoxManage snapshot $TEMPLATE take $SNAPSHOT_NAME
}
createVmFromShapshot(){
	VM="$1"
	TEMPLATE="$2"
	SNAPSHOT_NAME="$3"
	# Create VM from snapshot
	VBoxManage clonevm $TEMPLATE \
	  --options link --mode machine --snapshot $SNAPSHOT_NAME --name $VM --register
}
startVM(){
	VM="$1"
	VBoxManage startvm $VM --type headless
}
stopVM(){
	set +e
	VM="$1"
	VBoxManage controlvm "$VM" acpipowerbutton
	#VBoxManage controlvm "$VM" poweroff
	set -e
}
waitForReadyVM(){
	VM="$1"
	set +e
	while [ 1 ]; do
		CMD="VBoxManage guestcontrol $VM $COMMON_ARGS \
		  run --exe /bin/bash --timeout 5000 -- bash/arg0 \
		    -c 'id'"
		out="$(eval $CMD 2>&1)"
		exit_code=$?
		if [[ "$exit_code" == "0" ]]; then
			echo New VM is ready
			break
		fi
		echo "$out" | grep 'The guest execution service is not ready' >/dev/null || {
			echo "Unknown msg";
			echo CMD=$CMD;
			echo out=$out;
			echo exit_code=$exit_code;
			exit $exit_code;
		}
		echo "Waiting for new VM to be ready."
		sleep 1.0
	done
	set -e
}
bootstrapVM(){
       VM="$1"
       NEW_HOSTNAME="$2"
	VBoxManage guestcontrol $VM $COMMON_ARGS \
	  run \
	   -E HN=$NEW_HOSTNAME \
	   --exe /bin/bash --timeout 5000 -- bash/arg0 \
	    -c 'hostnamectl set-hostname $HN; rm /root/.ssh/authorized_keys /root/.ssh/known_hosts /etc/ssh/ssh_host_* /root/.ssh/id_* 2>/dev/null; \
	      ssh-keygen -f /etc/ssh/ssh_host_rsa_key -q -N \"\" -t rsa; ssh-keygen -q -N \"\" -t rsa -f /root/.ssh/id_rsa; \
	      mkdir -p /root/.ssh 2>/dev/null; chmod -R 700 /root/.ssh; chown -R root:root /root; systemctl restart sshd; \
	      systemctl status sshd' >/dev/null
}
showPortForwarding(){
	set +e
	(
		echo PORT_FORWARDING: && for vm in $(VBoxManage list -s runningvms|cut -d'{' -f2|cut -d'}' -f1); do
			VBoxManage showvminfo $vm > .info.txt
			NAME="$(cat .info.txt|grep '^Name: '|tr -s ' '|cut -d' ' -f2-100)"
			OS="$(cat .info.txt|grep 'Guest OS: '|tr -s ' '|cut -d' ' -f3-100)"
			NATS="$(VBoxManage showvminfo $vm|grep 'Rule' | sed 's/ //g'|cut -d':' -f2|tr ',' '\n'|sed 's/=/: /g'|yaml2json 2>&1 |jq -Mrc 2>/dev/null)"
			echo -e " - UUID: $vm\n   NAME: $NAME\n   OS: $OS\n   RULE: $NATS"
		done
	)	| yaml2json 2>/dev/null | jq
	set -e
}
createPortForward(){
	VM="$1"
	RULE_INDEX="$2"
	RULE_NAME="$3"
	LOCAL_PORT="$4"
	VM_PORT="$5"
	VBoxManage controlvm "$VM" natpf${RULE_INDEX} "${RULE_NAME},tcp,,${LOCAL_PORT},,${VM_PORT}"
}

deletePortForward(){
	VM="$1"
	RULE_INDEX="$2"
	RULE_NAME="$3"
	set +e
        while [ 1 ]; do
		cmd="VBoxManage modifyvm \"$VM\" --natpf${RULE_INDEX} delete \"$RULE_NAME\" 2>&1"
		out="$(eval $cmd)"
		exit_code=$?
		if [[ "$exit_code" == "0" ]]; then
			break
		fi
		echo $out|grep 'Invalid argument value' >/dev/null && break
		echo $out|grep 'is already locked for a session' >/dev/null || {
			echo exit_code=$exit_code;
			echo cmd=$cmd;
			echo out=$out;
		}
		sleep 1.0
	done
	set -e
}
copyPublicKey(){
	VM="$1"
	PUBLIC_KEY_FILE="$2"
	VBoxManage guestcontrol $VM -v $COMMON_ARGS copyto $PUBLIC_KEY_FILE /root/.ssh/authorized_keys
}
secureVM(){
	VM="$1"
	VBoxManage guestcontrol $VM -v $COMMON_ARGS \
	  run --exe /bin/bash --timeout 5000 -- bash/arg0 \
	    -c 'chown -R root:root /root; chmod -R 700 /root; systemctl enable sshd; systemctl start sshd; systemctl start sshd;' \
	| egrep -v '^waitResult:'
}
getAllClones(){
	VBoxManage list -s vms|cut -d'"' -f2|grep "^$TEMPLATE_BASE"|grep -v "${TEMPLATE_KEYWORD}$"
}
stopAllClones(){
    (	
	getAllClones \
		| xargs -I % echo "VBoxManage controlvm % acpipowerbutton 2>/dev/null"
    ) | bash
}
deleteAllClones(){
	set +e
	stopAllClones
    while [[ "$(eval getAllClones 2>/dev/null |wc -l)" -gt "0" ]]; do
	    (
		getAllClones \
			| xargs -I % echo "while [ 1 ]; do VBoxManage unregistervm % --delete 2>/dev/null && exit; sleep 1.0; done"
	    ) 	| bash
	    sleep 1.0
    done
    set -e
}
testServerSshConnection(){
	VM="$1"
	SSH_PORT="$2"
	cmd="command ssh -oPort=$SSH_PORT -oStrictHostKeyChecking=no -q root@127.0.0.1 hostname -f"
	eval $cmd >/dev/null
}
manageVM(){
	stopVM "$NEW_VM"
	deletePortForward "$NEW_VM" 1 ssh
	startVM "$NEW_VM"
	SSH_PORT="$(eval getNextForwardedHostPort)"
	createPortForward "$NEW_VM" 1 ssh $SSH_PORT 22
	showPortForwarding
	testServerSshConnection "$NEW_VM" $SSH_PORT
}
getForwardedHostPorts(){
	showPortForwarding 2>&1 | grep -i hostport|cut -d':' -f2|sed 's/[[:space:]]//g'|sed 's/,//g'| grep '^[0-9].*[0-9]$'|sort|uniq
}
getMaxForwardedHostPort(){
	getForwardedHostPorts | maxValueInList
}
getNextForwardedHostPort(){
	getMaxForwardedHostPort | xargs -I % echo "% + 1"| bc
}
maxValueInList(){
	awk 'min == "" || $1<min{min=$1} $1>max{max=$1} END{print max}'
}
portDemo(){
	#getForwardedHostPorts
	#getMaxForwardedHostPort
	getNextForwardedHostPort
}
createVM(){
	#deleteAllClones
	snapshotVM "$TEMPLATE" "$SNAPSHOT_NAME"
	createVmFromShapshot "$NEW_VM" "$TEMPLATE" "$SNAPSHOT_NAME"
	startVM "$NEW_VM"
	waitForReadyVM "$NEW_VM"
	bootstrapVM "$NEW_VM" "$NEW_HOSTNAME"
	copyPublicKey "$NEW_VM" "$PUBLIC_KEY_FILE"
	secureVM "$NEW_VM"
	showPortForwarding
}

main() {
    if [[ "1" == "0" ]]; then
        "${1}"
    else
        echo
	#portDemo
	#manageVM
	createVM
        echo
    fi
}

main "${@}"
