#!/bin/bash
set -e
VM="$1"
_WIREGUARD_SERVER_ENDPOINT="${_WIREGUARD_SERVER_ENDPOINT_DOMAIN}:${_WIREGUARD_SERVER_ENDPOINT_PORT}"
if [[ "$_WIREGUARD_SERVER_ENDPOINT" == ":" ]]; then echo invalid _WIREGUARD_SERVER_ENDPOINT; exit 1; fi
_WIREGUARD_CLIENT_ROUTES="216.239.0.0/16,123.123.123.0/24,10.14.0.2/32"
SSH_OPTS="-oStrictHostKeyChecking=no -q"
VM_PACKAGES="rsync tcpdump ngrep telnet"
RSYNC_OPTS="-e 'ssh $SSH_OPTS'"
RSYNC_OPTS=""
INSTALL_VM_PATH="/root/.wireguard_installer"
REMOVE_INSTALLER_CMD="rm -rf /root/.wireguard_installer"
INSTALL_FILES="files/common.sh files/setupWireguardVM.sh files/wg-json"
POST_INSTALL_CMD="mv $INSTALL_VM_PATH/wg-json /usr/sbin/."
INSTALL_CMD="bash -e $INSTALL_VM_PATH/setupWireguardVM.sh"
VALIDATION_CMD="wg"
PUBLIC_KEY_PATH="/etc/wireguard/publickey"
PRIVATE_KEY_PATH="/etc/wireguard/privatekey"
LOCAL_VM_PUBLIC_KEY_FILE="$(pwd)/.${VM}.pub"
WIREGUARD_INTERFACE="wg0"
WIREGUARD_CONFIG="/etc/wireguard/${WIREGUARD_INTERFACE}.conf"
CLIENT_IP_SUFFIX_MIN="2"
CLIENT_IP_SUFFIX_MAX="250"
_SUBNET="10.14."
WG_SAVE_CMD="wg-quick save $WIREGUARD_INTERFACE"
GET_CLIENT_IP_CMD="echo \$(( ( RANDOM % $CLIENT_IP_SUFFIX_MAX )  + $CLIENT_IP_SUFFIX_MIN ))"
GET_CLIENT_IP_SUFFIXES_IN_USE_CMD_ENCODED=$(echo "wg|grep allowed|grep -oE \"\b([0-9]{1,3}\.){3}[0-9]{1,3}\b\"|sed \"s/${_SUBNET}//g\"|sort|uniq"|base64 -w0)
SETUP_WIREGUARD_CLIENT_CMD_ENCODED=$(echo '
sed -i "s/[[:space:]]//g" /root/vars.sh
source /root/vars.sh;
mkdir -p /etc/wireguard 2>/dev/null; 
cd /etc/wireguard; 
ip link add dev $WIREGUARD_INTERFACE type wireguard 2>/dev/null;
ip address add dev $WIREGUARD_INTERFACE ${_WIREGUARD_CLIENT_ADDRESS}/32 2>/dev/null;
wg set $WIREGUARD_INTERFACE private-key $PRIVATE_KEY_PATH peer ${_WIREGUARD_SERVER_PUBLIC_KEY} endpoint ${WIREGUARD_SERVER_ENDPOINT} persistent-keepalive 25 allowed-ips ${_WIREGUARD_CLIENT_ROUTES}; 
wg showconf $WIREGUARD_INTERFACE > $WIREGUARD_CONFIG; 
wg setconf $WIREGUARD_INTERFACE $WIREGUARD_CONFIG; 
cat $WIREGUARD_CONFIG; 
wg; 
ip link set up dev $WIREGUARD_INTERFACE; 
(echo "[Interface]"; echo "Address = $_WIREGUARD_CLIENT_ADDRESS"; cat /etc/wireguard/wg0.conf |grep -v "\[Interface\]") > t && mv -f t /etc/wireguard/wg0.conf;
chmod -R 600 /etc/wireguard;
chown -R root:root /etc/wireguard;
wg-quick down $WIREGUARD_INTERFACE; 
wg-quick up $WIREGUARD_INTERFACE; 
wg; 
wg-quick down wg0;
systemctl enable wg-quick@wg0;
systemctl restart wg-quick@wg0;
systemctl status wg-quick@wg0;
timeout 10 curl -4s https://ifconfig.me;
'|base64 -w0)
GET_WIREGUARD_PUBLIC_KEY_CMD="wg show wg0 public-key"
GET_WIREGUARD_PORT_CMD="wg show wg0 listen-port"
GET_WIREGUARD_INTERFACES_CMD="wg show wg0 interfaces"
GET_CLIENT_IP_SUFFIXES_IN_USE_CMD="echo \"$GET_CLIENT_IP_SUFFIXES_IN_USE_CMD_ENCODED\"|base64 -d > script.sh && bash -ex script.sh"
SETUP_WIREGUARD_CLIENT_CMD="echo \"$SETUP_WIREGUARD_CLIENT_CMD_ENCODED\"|base64 -d > script.sh && bash -x script.sh"
GET_WIREGUARD_SERVER_IP_CMD="grep ^Address $WIREGUARD_CONFIG |grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'"
#GET_WIREGUARD_SERVER_IP_CMD="ifconfig wg0|grep inet|grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'|grep ^10.14.|head -n 1'"
SUFFIXES_IN_USE_FILE=`mktemp`
IPS_IN_USE_FILE=`mktemp`
SERVER_PUBLIC_KEY_FILE=`mktemp`
SERVER_IP_FILE=`mktemp`
GET_RANDOM_CLIENT_IP_SUFFIX(){
    echo $(( ( RANDOM % $CLIENT_IP_SUFFIX_MAX )  + $CLIENT_IP_SUFFIX_MIN ))
}

command ssh $SSH_OPTS root@vpnservice.company "sh -c \"$GET_CLIENT_IP_SUFFIXES_IN_USE_CMD\"" > $SUFFIXES_IN_USE_FILE
command ssh $SSH_OPTS root@vpnservice.company "sh -c \"cat $PUBLIC_KEY_PATH\"" > $SERVER_PUBLIC_KEY_FILE
command ssh $SSH_OPTS root@vpnservice.company "$GET_WIREGUARD_SERVER_IP_CMD" > $SERVER_IP_FILE

WIREGUARD_SERVER_IP="$(cat $SERVER_IP_FILE)"
_WIREGUARD_SERVER_PUBLIC_KEY="$(cat $SERVER_PUBLIC_KEY_FILE)"
[[ "$DEBUG_MODE" == "1" ]] && echo "There are $(cat $SUFFIXES_IN_USE_FILE|wc -l|cut -d' ' -f1) IP Suffixes in use in subnet ${_SUBNET}"

(
        while IFS= read -r SUFFIX; do
           SUFFIX="$(echo $SUFFIX|sed 's/[[:space:]]//g'|head -n1)"
           #echo IP=${_SUBNET}${SUFFIX}
           echo "_${SUFFIX}_"
         done < $SUFFIXES_IN_USE_FILE
                                            ) > $IPS_IN_USE_FILE

ip_is_available(){
    IP="$1"
    grep -c "_${IP}_" $IPS_IN_USE_FILE
}
suffixToIP(){
    echo "${_SUBNET}$1"
}
getRandomOctet(){
  echo $(( RANDOM % 256 ))
}

getRandomIP(){
    IP="${_SUBNET}$(getRandomOctet).$(getRandomOctet)"
    echo $IP
}

_WIREGUARD_CLIENT_ADDRESS=$(getRandomIP)
while [[ "$(eval ip_is_available "$_WIREGUARD_CLIENT_ADDRESS")" -gt "0" ]]; do
    _WIREGUARD_CLIENT_ADDRESS=$(getRandomIP)
    ((CUR_SUFFIX++))
done

echo _WIREGUARD_CLIENT_ADDRESS=$_WIREGUARD_CLIENT_ADDRESS


echo Found Client Address ${_WIREGUARD_CLIENT_ADDRESS}

command ssh $SSH_OPTS $VM "sh -c \"rm -rf $INSTALL_VM_PATH 2>/dev/null; mkdir -p $INSTALL_VM_PATH 2>/dev/null; dnf -y install $VM_PACKAGES\""
command rsync -ar $RSYNC_OPTS $INSTALL_FILES ${VM}:${INSTALL_VM_PATH}/.
command ssh $SSH_OPTS $VM "\
    SUBNET=\"$_SUBNET\" \
    WIREGUARD_CLIENT_ADDRESS=\"$_WIREGUARD_CLIENT_ADDRESS\" \
    _WIREGUARD_CLIENT_ROUTES=\"$_WIREGUARD_CLIENT_ROUTES\" \
    WIREGUARD_SERVER_ENDPOINT=\"$_WIREGUARD_SERVER_ENDPOINT\" \
    WIREGUARD_SERVER_PUBLIC_KEY=\"$_WIREGUARD_SERVER_PUBLIC_KEY\" \
    PUBLIC_KEY_PATH=\"$PUBLIC_KEY_PATH\" \
    sh -c \"$INSTALL_CMD && $POST_INSTALL_CMD && echo Running Remove Installer && $REMOVE_INSTALLER_CMD && echo Removed Installer && $VALIDATION_CMD\""


command rsync $RSYNC_OPTS ${VM}:$PUBLIC_KEY_PATH $LOCAL_VM_PUBLIC_KEY_FILE

CLIENT_PUBLIC_KEY="$(cat $LOCAL_VM_PUBLIC_KEY_FILE)"
SETUP_CLIENT_ON_SERVER_CMD="wg set $WIREGUARD_INTERFACE peer $CLIENT_PUBLIC_KEY allowed-ips ${_WIREGUARD_CLIENT_ADDRESS}/32 && $WG_SAVE_CMD"

echo -e "\nSETUP_CLIENT_ON_SERVER_CMD=\n   $SETUP_CLIENT_ON_SERVER_CMD\n"

command ssh $SSH_OPTS root@vpnservice.company "sh -c \"$SETUP_CLIENT_ON_SERVER_CMD\""
exit_code=$?
echo SETUP_CLIENT_ON_SERVER_CMD exit_code=$exit_code



CLIENT_SETUP_VARS_FILE=`mktemp`
CLIENT_SETUP_VARS="WIREGUARD_INTERFACE=\"$WIREGUARD_INTERFACE\"
_WIREGUARD_CLIENT_ADDRESS=\"$_WIREGUARD_CLIENT_ADDRESS\"
WIREGUARD_SERVER_IP=\"$WIREGUARD_SERVER_IP\"
PRIVATE_KEY_PATH=\"$PRIVATE_KEY_PATH\"
_WIREGUARD_SERVER_PUBLIC_KEY=\"$_WIREGUARD_SERVER_PUBLIC_KEY\"
WIREGUARD_SERVER_ENDPOINT=\"$_WIREGUARD_SERVER_ENDPOINT\"
_WIREGUARD_CLIENT_ROUTES=\"$_WIREGUARD_CLIENT_ROUTES\"
WIREGUARD_CONFIG=\"$WIREGUARD_CONFIG\""


echo "$CLIENT_SETUP_VARS" > $CLIENT_SETUP_VARS_FILE
cat $CLIENT_SETUP_VARS_FILE
ls -al $CLIENT_SETUP_VARS_FILE


command rsync $RSYNC_OPTS $CLIENT_SETUP_VARS_FILE $VM:/root/vars.sh
echo -e "\nSETUP_WIREGUARD_CLIENT_CMD=\n   $SETUP_WIREGUARD_CLIENT_CMD\n"
command ssh $SSH_OPTS $VM "$SETUP_WIREGUARD_CLIENT_CMD"
exit_code=$?
echo SETUP_WIREGUARD_CLIENT_CMD exit_code=$exit_code
