#!/usr/bin/env bash
set -e -o pipefail
cd $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

. .bash-concurrent/concurrent.lib.sh
set +e
command yaml2json --version >/dev/null 2>&1 || . ~/.venv/bin/activate
set -e

VM_MIN_ID=100
VM_MAX_ID=1000
TEMPLATE_BASE=centos-8-
TEMPLATE_KEYWORD=template
VM_SUFFIX="$1"
VM_PREFIX="vm"
NEW_VM=${TEMPLATE_BASE}${VM_SUFFIX}
NEW_HOSTNAME=$NEW_VM
TEMPLATE=${TEMPLATE_BASE}${TEMPLATE_KEYWORD}
SNAPSHOT_NAME=${TEMPLATE_KEYWORD}-wireguard1
export B64_DECODE_FLAG=$(set +e; echo 123 | base64 |base64 -d 2>/dev/null |grep -q 123 && echo d || echo D)
timeout=$(set +e; (command -v timeout || command -v gtimeout || brew install coreutils && command -v gtimeout|grep timeout |head -n1))



PUBLIC_KEY_FILE=`mktemp`
echo "$_PUBLIC_KEY"|base64 -$B64_DECODE_FLAG 2>/dev/null > $PUBLIC_KEY_FILE

cat $PUBLIC_KEY_FILE|grep -q ^ssh-rsa

[[ "$PASS" == "" ]] && export PASS=12341234
COMMON_ARGS="--username root --password $PASS"
SSHCONFIG="$(pwd)/.sshconfig/sshconfig"
SSH_COMMON_OPTS="-q -oStrictHostKeyChecking=no"
if [[ "$DEBUG_MODE" == "" ]]; then export DEBUG_MODE=="0"; fi
MANAGED_VM_SUFFIX_RE1='^[0-9]+$'
MANAGED_VM_SUFFIX_RE2='^vm[0-9]+$'

addHostToSshConfig(){
	VM="$1"
	HOST_SSH_PORT="$2"
	set +e
	cmd="$SSHCONFIG rm \"$VM\" >/dev/null 2>&1"
    eval $cmd
    cmd="$SSHCONFIG add "$VM" root 127.0.0.1 $HOST_SSH_PORT"
    out="$(eval $cmd)"
	exit_code=$?
	if [[ "$exit_code" != "0" ]]; then
			echo cmd=$cmd;
			echo out=$out;
			echo exit_code=$exit_code;
			exit $exit_code;
    fi
	set -e
}
snapshotVM(){
    TEMPLATE="$1"
    SNAPSHOT_NAME="$2"
    #VBoxManage snapshot $TEMPLATE list|grep "Name: $SNAPSHOT_NAME (UUID: " >/dev/null || \
    listSnapshots "$TEMPLATE" |grep "Name: $SNAPSHOT_NAME (UUID: " >/dev/null || \
        VBoxManage snapshot $TEMPLATE take $SNAPSHOT_NAME
}
listSnapshots(){
    VM="$1"
    VBoxManage snapshot "$VM" list
}
deleteSnapshot(){
    VM="$1"
    SNAPSHOT_NAME="$2"
    set -e
    VBoxManage snapshot "$VM" delete "$SNAPSHOT_NAME"
}
vmExists(){
	VM="$1"
	getAllVMs | grep -q "^${VM}$"
}
normalizeNewVMName(){
	VM="$1"
#	if echo "$VM" | grep -q "\-${VM_PREFIX}"; then export VM="${VM_PREFIX}${VM}"; fi
	if echo "$VM" | grep -q '\-random$'; then
		_VM="$VM"
		getAllVMs > .vms.txt
		echo "$VM" >> .vms.txt
		while $(grep -q "^$VM$" .vms.txt); do
			echo "vm exists..."
			sleep .1
			R=$(( ( RANDOM % $VM_MAX_ID )  + $VM_MIN_ID ))
			VM=$(echo "$_VM"|sed "s/-random/$R/g" )
		done
		rm .vms.txt
	fi
#	echo "$VM" | grep -q "{$TEMPLATE_BASE}" || export VM="${TEMPLATE_BASE}${VM}"
	echo "$VM"
}
createVmFromShapshot(){
	VM="$1"
	TEMPLATE="$2"
	SNAPSHOT_NAME="$3"
	set -e
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
	SHUTDOWN=0
	MAX_SECS=15
	$timeout $MAX_SECS VBoxManage controlvm "$VM" acpipowerbutton
       #	| grep 'is not currently running' && exit
#	while [[ "$SHUTDOWN" == "0" ]]; do
#		($timeout $MAX_SECS VBoxManage controlvm "$VM" acpipowerbutton 2>&1)|grep 'is not currently running' && exit
#			echo "VM $VM not shutdown $MAX_SECS seconds after power button pressed." && \
#				timeout $MAX_SECS VBoxManage controlvm "$VM" poweroff
#
#		sleep 1.0
#	done
	set -e
}
waitForReadyVM(){
	VM="$1"
	set +e
	while [ 1 ]; do
		cmd="VBoxManage guestcontrol $VM $COMMON_ARGS \
		  run --exe /bin/bash --timeout 5000 -- bash/arg0 \
		    -c 'id'"
		out="$(eval $cmd 2>&1)"
		exit_code=$?
		if [[ "$exit_code" == "0" ]]; then
			echo New VM is ready
			break
		fi
		echo "$out" | grep 'The guest execution service is not ready' >/dev/null || {
			echo "Unknown msg";
			echo cmd=$cmd;
			echo out=$out;
			echo exit_code=$exit_code;
			exit $exit_code;
		}
		echo "Waiting for new VM to be ready."
        if [[ "$DEBUG_MODE" == "1" ]]; then
			echo exit_code=$exit_code;
			echo cmd=$cmd;
			echo out=$out;
        fi
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
	      ssh-keygen -f /etc/ssh/ssh_host_rsa_key -q -N "" -t rsa; ssh-keygen -q -N "" -t rsa -f ~/.ssh/id_rsa; \
	      mkdir -p /root/.ssh 2>/dev/null; chmod -R 700 /root/.ssh; chown -R root:root /root; systemctl restart sshd; \
	      systemctl status sshd' >/dev/null
}
vmCommand(){
	VM="$1"
	CMD="$2"
	cmd="VBoxManage guestcontrol \"$VM\" $COMMON_ARGS run --exe /bin/bash --timeout 5000 -- bash/arg0 -c \"$CMD\""
	echo "$cmd"
	eval $cmd
	exit_code=$?
}
showPortForwarding(){
	set +e
	(
		echo PORT_FORWARDING: && for vm in $(VBoxManage list -s runningvms|cut -d'{' -f2|cut -d'}' -f1); do
			VBoxManage showvminfo $vm > .info.txt
			NAME="$(cat .info.txt|grep '^Name: '|tr -s ' '|cut -d' ' -f2-100)"
			OS="$(cat .info.txt|grep 'Guest OS: '|tr -s ' '|cut -d' ' -f3-100)"
            VBoxManage showvminfo $vm|grep 'Rule' | sed 's/ //g'|cut -d':' -f2 > .NATS-${vm}.txt
            while IFS= read -r NAT; do
                _NAT="$(echo $NAT|tr ',' '\n'|sed 's/=/: /g'|yaml2json 2>&1 |jq -Mrc 2>/dev/null)"
			    echo -e " - UUID: $vm\n   NAME: $NAME\n   OS: $OS\n   RULE: $_NAT"
            done < .NATS-${vm}.txt
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
        if [[ "$DEBUG_MODE" == "1" ]]; then
			echo exit_code=$exit_code;
			echo cmd=$cmd;
			echo out=$out;
        fi
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
	    -c 'chown -R root:root /root; chmod -R 700 /root; systemctl enable sshd; systemctl start sshd; systemctl status sshd;' \
	| egrep -v '^waitResult:'
}
getAllVMs_raw(){
    VBoxManage list -s vms
}
getAllVMs(){
    getAllVMs_raw | cut -d'"' -f2
}
getAllClones(){
	getAllVMs|grep "^$TEMPLATE_BASE"|grep -v "${TEMPLATE_KEYWORD}$"
}
stopAllClones(){
    (	
	getAllClones \
		| xargs -I % echo "VBoxManage controlvm % acpipowerbutton"
    )|xargs -P 3 -I % sh -c "%"
}
deleteVM(){
   	export VM="$1"
    echo "$1" | grep "^$TEMPLATE_BASE" >/dev/null ||
    	export VM="${TEMPLATE_BASE}$1"
    echo "$VM" | grep "^$TEMPLATE_BASE" >/dev/null || {
        echo Invalid VM $VM
        exit 1
    }
#    if ! [[ "$1" =~ "$MANAGED_VM_SUFFIX_RE1" ]] && ! [[ "$1" =~ "$MANAGED_VM_SUFFIX_RE2" ]]; then
#        echo "Invalid VM suffix. (VM=$VM)"
#        exit 1
#    fi
    set +e
    cmd="VBoxManage controlvm "$VM" poweroff 2>/dev/null; VBoxManage unregistervm $VM --delete"
    eval $cmd
    exit_code=$?
	if [[ "$exit_code" == "0" ]]; then
        set -e
        return
    else
        echo cmd=$cmd;
        echo out=$out;
        echo exit_code=$exit_code;
        exit $exit_code;
    fi
}
deleteAllClones(){
	set +e
	stopAllClones 2>/dev/null
	while [[ "$(eval getAllClones 2>/dev/null |wc -l)" -gt "0" ]]; do
		(
		  for c in $(getAllClones|egrep "^${TEMPLATE_BASE}vm[0-9]|^${TEMPLATE_BASE}[0-9]"); do
		    cmd="deleteVM \"$c\""
		    eval $cmd
		  done
		)
		sleep 1.0
	done
    set -e
}
testServerSshConnection(){
	VM="$1"
	SSH_PORT="$2"
	cmd="command ssh $SSH_COMMON_OPTS -oPort=$SSH_PORT root@127.0.0.1 hostname -f"
	eval $cmd >/dev/null
}
manageVM(){
	stopVM "$NEW_VM"
	deletePortForward "$NEW_VM" 1 ssh
	startVM "$NEW_VM"
	SSH_PORT="$(eval getNextForwardedHostPort)"
	showPortForwarding
	echo "Forwarding on port $SSH_PORT"
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
validateNewVM(){
	VM="$1"
	set -e
	cmd="command ssh $SSH_COMMON_OPTS "$VM" cat /etc/redhat-release"
	eval $cmd >/dev/null
	cmd="command ssh $SSH_COMMON_OPTS "$VM" hostname -f"
	eval $cmd > /dev/null
}
createVM(){
	[[ "$_DELETE_ALL_CLONES" == "1" ]] && deleteAllClones
	snapshotVM "$TEMPLATE" "$SNAPSHOT_NAME"
	createVmFromShapshot "$NEW_VM" "$TEMPLATE" "$SNAPSHOT_NAME"
    	#deleteSnapshot "$TEMPLATE" "$SNAPSHOT_NAME"
	stopVM "$NEW_VM"
	deletePortForward "$NEW_VM" 1 ssh
	startVM "$NEW_VM"
	waitForReadyVM "$NEW_VM"
	bootstrapVM "$NEW_VM" "$NEW_HOSTNAME"
	copyPublicKey "$NEW_VM" "$PUBLIC_KEY_FILE"
	secureVM "$NEW_VM"
	SSH_PORT="$(eval getNextForwardedHostPort)"
	createPortForward "$NEW_VM" 1 ssh $SSH_PORT 22
	addHostToSshConfig "$NEW_VM" $SSH_PORT
	addHostToSshConfig "$VM_SUFFIX" $SSH_PORT
	validateNewVM "$NEW_VM"
	[[ "$_INSTALL_WIREGUARD" == "1" ]] && time ./install_vm_wireguard.sh "$NEW_VM"
}

main() {
    if [[ "$1" == "template" ]]; then echo Cannot manage template; exit 1; fi
    if ! [[ $1 =~ $MANAGED_VM_SUFFIX_RE1 ]] && ! [[ $1 =~ $MANAGED_VM_SUFFIX_RE2 ]]; then
        "${1}" "$2" "$3" "$4" "$5" "$6" "$7"
    else
        #portDemo
        #manageVM
        createVM
        echo
    fi
}

main "${@}"
