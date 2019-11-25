#!/usr/bin/env bash
set -e -o pipefail
cd $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

. .bash-concurrent/concurrent.lib.sh

TEMPLATE_BASE=centos-8-
TEMPLATE_KEYWORD=template
NEW_VM=${TEMPLATE_BASE}$1
NEW_HOSTNAME=$NEW_VM
TEMPLATE=${TEMPLATE_BASE}${TEMPLATE_KEYWORD}
SNAPSHOT_NAME=${TEMPLATE_KEYWORD}-snapshot
PUBIC_KEY_FILE=~/.ssh/id_rsa.pub
[[ "$PASS" == "" ]] && export PASS=12341234
COMMON_ARGS="--username root --password $PASS"

success() {
    local args=(
        - "Creating VM"                                         create_vm    3.0
        - "Creating ramdisk"                                    my_sleep     0.1
        - "Enabling swap"                                       my_sleep     0.1
        - "Populating VM with world data"                       restore_data 5.0
        - "Spigot: Pulling docker image for build"              my_sleep     0.5
        - "Spigot: Building JAR"                                my_sleep     6.0
        - "Pulling remaining docker images"                     my_sleep     2.0
        - "Launching services"                                  my_sleep     0.2

        --require "Creating VM"
        --before  "Creating ramdisk"
        --before  "Enabling swap"

        --require "Creating ramdisk"
        --before  "Populating VM with world data"
        --before  "Spigot: Pulling docker image for build"

        --require "Spigot: Pulling docker image for build"
        --before  "Spigot: Building JAR"
        --before  "Pulling remaining docker images"

        --require "Populating VM with world data"
        --require "Spigot: Building JAR"
        --require "Pulling remaining docker images"
        --before  "Launching services"
    )

    concurrent "${args[@]}"
}

create_vm() {
    local provider=digitalocean
    echo "(on ${provider})" >&3
    my_sleep "${@}"
}

restore_data() {
    local data_source=dropbox
    echo "(with ${data_source})" >&3
    my_sleep "${@}"
}

my_sleep() {
    local seconds=${1}
    local code=${2:-0}
    echo "Yay! Sleeping for ${seconds} second(s)!"
    sleep "${seconds}"
    if [ "${code}" -ne 0 ]; then
        echo "Oh no! Terrible failure!" 1>&2
    fi
    return "${code}"
}

secureVM(){
	VM="$1"
	VBoxManage guestcontrol $VM -v $COMMON_ARGS \
	  run --exe /bin/bash --timeout 5000 -- bash/arg0 \
	    -c 'chown -R root:root /root; chmod -R 700 /root; systemctl enable sshd; systemctl start sshd; systemctl start sshd;' \
	| egrep -v '^waitResult:'
}
createVmFromShapshot(){
	VM="$1"
	TEMPLATE="$2"
	SNAPSHOT_NAME="$3"
	# Create VM from snapshot
	time VBoxManage clonevm $TEMPLATE \
	  --options link --mode machine --snapshot $SNAPSHOT_NAME --name $VM --register
}
snapshotVM(){
       TEMPLATE="$1"
       SNAPSHOT_NAME="$2"
	VBoxManage snapshot $TEMPLATE list|grep "Name: $SNAPSHOT_NAME (UUID: " >/dev/null || 
	  VBoxManage snapshot $TEMPLATE take $SNAPSHOT_NAME
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
	      systemctl status sshd'
}
showPortForwarding(){
	(
		echo PORT_FORWARDING: && for vm in $(VBoxManage list -s runningvms|cut -d'{' -f2|cut -d'}' -f1); do
			VBoxManage showvminfo $vm > .info.txt
			NAME="$(cat .info.txt|grep '^Name: '|tr -s ' '|cut -d' ' -f2-100)"
			OS="$(cat .info.txt|grep 'Guest OS: '|tr -s ' '|cut -d' ' -f3-100)"
			NATS="$(VBoxManage showvminfo $vm|grep '^NIC 1 R'|sed 's/ //g'|cut -d':' -f2|tr ',' '\n'|sed 's/=/: /g'|yaml2json 2>&1 |jq -Mrc 2>/dev/null)"
			echo -e " - UUID: $vm\n   NAME: $NAME\n   OS: $OS\n   RULE: $NATS"
		done
	)	| yaml2json 2>/dev/null | jq
}
startVM(){
	VM="$1"
	VBoxManage startvm $VM --type headless
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
		echo "$out" | grep 'The guest execution service is not ready' || {
			echo "Unknown msg";
			echo CMD=$CMD;
			echo out=$out;
			echo exit_code=$exit_code;
			exit $exit_code;
		}
		echo Waiting for new VM to be ready
		echo "$out" |head -n1
		echo CMD=$CMD
		echo out=$out
		echo exit_code=$exit_code
		sleep 5.0
	done
	set -e
}
copyPublicKey(){
	VM="$1"
	PUBIC_KEY_FILE="$2"
	VBoxManage guestcontrol $VM -v $COMMON_ARGS copyto $PUBIC_KEY_FILE /root/.ssh/authorized_keys
}
createVM(){
	deleteAllClones
	#exit
	snapshotVM "$TEMPLATE" "$SNAPSHOT_NAME"
	createVmFromShapshot "$NEW_VM" "$TEMPLATE" "$SNAPSHOT_NAME"
	startVM "$NEW_VM"
	waitForReadyVM "$NEW_VM"
	bootstrapVM "$NEW_VM" "$NEW_HOSTNAME"
	copyPublicKey "$NEW_VM" "$PUBIC_KEY_FILE"
	secureVM "$NEW_VM"
	showPortForwarding
}

main() {
    if [[ -n "${1}" ]]; then
        "${1}"
    else
        echo
        echo "[SUCCESS EXAMPLE]"
        success
        echo
        echo "[FAILURE EXAMPLE]"
        failure
    fi
}

createVM
#main "${@}"
