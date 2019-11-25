#!/bin/bash
set -e
TEMPLATE_BASE=centos-8-
TEMPLATE_KEYWORD=template
NEW_VM=${TEMPLATE_BASE}$1
NEW_HOSTNAME=$NEW_VM
TEMPLATE=${TEMPLATE_BASE}${TEMPLATE_KEYWORD}
SNAPSHOT_NAME=${TEMPLATE_KEYWORD}-snapshot
PUBIC_KEY_FILE=~/.ssh/id_rsa.pub
[[ "$PASS" == "" ]] && export PASS=12341234
COMMON_ARGS="--username root --password $PASS"


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
			| xargs -I % echo "while [ 1 ]; do VBoxManage unregistervm % --delete && exit; sleep 1.0; done"
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

deleteAllClones
#getAllClones
#stopAllClones
#exit

# Create Snapshot from Template VM
VBoxManage snapshot $TEMPLATE list|grep "Name: $SNAPSHOT_NAME (UUID: " >/dev/null || 
  VBoxManage snapshot $TEMPLATE take $SNAPSHOT_NAME

# Create VM from snapshot
time VBoxManage clonevm $TEMPLATE \
  --options link --mode machine --snapshot $SNAPSHOT_NAME --name $NEW_VM --register

# Start VM
VBoxManage startvm $NEW_VM --type headless

# Wait for VM to be ready
waitForReadyVM "$NEW_VM"

# Bootstrap VM
VBoxManage guestcontrol $NEW_VM $COMMON_ARGS \
  run \
   -E HN=$NEW_HOSTNAME \
   --exe /bin/bash --timeout 5000 -- bash/arg0 \
    -c 'hostnamectl set-hostname $HN; rm /root/.ssh/authorized_keys /root/.ssh/known_hosts /etc/ssh/ssh_host_* /root/.ssh/id_* 2>/dev/null; \
      ssh-keygen -f /etc/ssh/ssh_host_rsa_key -q -N \"\" -t rsa; ssh-keygen -q -N \"\" -t rsa -f /root/.ssh/id_rsa; \
      mkdir /root/.ssh; chmod -R 700 /root/.ssh; chown -R root:root /root; systemctl restart sshd; \
      systemctl status sshd'

# Copy Public Key
VBoxManage guestcontrol $NEW_VM -v $COMMON_ARGS copyto $PUBIC_KEY_FILE /root/.ssh/authorized_keys

# Secure VM
VBoxManage guestcontrol $NEW_VM -v $COMMON_ARGS \
  run --exe /bin/bash --timeout 5000 -- bash/arg0 \
    -c 'chown -R root:root /root; chmod -R 700 /root; systemctl enable sshd; systemctl start sshd; systemctl start sshd;' \
| egrep -v '^waitResult:'

