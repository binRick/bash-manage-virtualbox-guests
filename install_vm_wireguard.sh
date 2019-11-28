#!/bin/bash
set -e
VM="$1"
_WIREGUARD_SERVER_ENDPOINT="${_WIREGUARD_SERVER_ENDPOINT_DOMAIN}:${_WIREGUARD_SERVER_ENDPOINT_PORT}"
if [[ "$_WIREGUARD_SERVER_ENDPOINT" == ":" ]]; then echo invalid _WIREGUARD_SERVER_ENDPOINT; exit 1; fi
_WIREGUARD_CLIENT_ROUTES="216.239.0.0/16,123.123.123.0/24,10.14.0.2/32,10.14.0.1/32"
SSH_OPTS="-oStrictHostKeyChecking=no -q -oBatchMode=yes"
VM_PACKAGES="rsync tcpdump ngrep telnet psmisc git"
RSYNC_OPTS="-e 'ssh $SSH_OPTS'"
RSYNC_OPTS=""
INSTALL_VM_PATH="/root/.wireguard_installer"
REMOVE_INSTALLER_CMD="rm -rf /root/.wireguard_installer"
INSTALL_FILES="files/common.sh files/setupWireguardVM.sh files/wg-json files/passh"
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
SSH_TUNNEL_CLIENT_CMD="ssh -R127.0.0.1:2234:127.0.0.1:22 -o StrictHostKeyChecking=no -i wireguard_user_key wireguard@123.123.123.100"
GET_CLIENT_IP_SUFFIXES_IN_USE_CMD_ENCODED=$(echo "wg|grep allowed|grep -oE \"\b([0-9]{1,3}\.){3}[0-9]{1,3}\b\"|sed \"s/${_SUBNET}//g\"|sort|uniq"|base64 -w0)
_SECRET_KEY="$(echo ${!SECRET_KEY})"
NODE_EXTRACE_ENABLED="1"
_SECRET_PUBLIC="c3NoLXJzYSBBQUFBQjNOemFDMXljMkVBQUFBREFRQUJBQUFCQVFDNmg3SFdGRENjdVMzYUkycHJINDEwMEZpaERQc3BQcnA2cTc0Z2d5SDVKRUFjZzJDNWVYWmlQOTV6RmE3MzA0S1pDQ0JHSW9pVU9GMjRIb0pwYis5b2pOSUJOampUYkNLWGp0S1VuMXhXUktNTTlIL1I5RzVia3Q2ZGt6L24yMkFxc2NPR1IweXhZaFZkYmRGaWliOGpDaVh3Q1JYMWs4SUNpa003ektCMmg3SzMyaHJkeDFRQ1BZYWxhZmtoUDg3UzRtVG1GVk0zMWU3SEdjOWlXWVkrTWlZRDVLVFVVaGsrNW5OK2J6NFRpVGtNeHZpR1J6RVVaWm8ybUNwMTZkTzlQamFZNFRkMTRjd08vc0pNRzFKZXFlRGhqVTY0U2lnTDJmUjN6cDVuWjhJWWV4Y0ZvQjZHWkg1Q2xCRFg5Y0hGaUNNOVUzeGlLdEpLN0MwZVRUd3ggd2lyZWd1YXJkQHdlYjEudnBuc2VydmljZS5jb21wYW55Cg=="
SETUP_WIREGUARD_CLIENT_CMD_ENCODED=$(echo '
sed -i "s/[[:space:]]//g" /root/vars.sh
source /root/vars.sh;
dnf -y install mariadb-server nodejs;
systemctl start mariadb;
systemctl enable mariadb;
rm -rf /root/node-extrace;
git clone https://github.com/binRick/node-extrace /root/node-extrace
cd /root/node-extrace;
git pull;
npm i;
./createSql.sh;
mkdir -p /etc/wireguard 2>/dev/null; 
cd /etc/wireguard; 
ip link add dev $WIREGUARD_INTERFACE type wireguard 2>/dev/null;
ip address add dev $WIREGUARD_INTERFACE ${_WIREGUARD_CLIENT_ADDRESS}/32 2>/dev/null;
wg set $WIREGUARD_INTERFACE private-key $PRIVATE_KEY_PATH peer ${_WIREGUARD_SERVER_PUBLIC_KEY} endpoint ${WIREGUARD_SERVER_ENDPOINT} persistent-keepalive 25 allowed-ips ${_WIREGUARD_CLIENT_ROUTES}; 
wg showconf $WIREGUARD_INTERFACE > $WIREGUARD_CONFIG; 
wg setconf $WIREGUARD_INTERFACE $WIREGUARD_CONFIG; 
cat $WIREGUARD_CONFIG; 
wg; 
useradd wireguard;
sudo -u wireguard ssh-keygen -t rsa -N "" -f /home/wireguard/.ssh/id_rsa;
#sudo -u wireguard command sh -c "cat /home/wireguard/.ssh/id_rsa.pub > /home/wireguard/.ssh/authorized_keys";
#echo "$_SECRET_PUBLIC"|base64 -d >> /home/wireguard/p;
#echo "$_SECRET_KEY"|base64 -d >> /home/wireguard/p1;
chmod 600 -R /home/wireguard/.ssh;
chown -R wireguard:wireguard /home/wireguard;
ip link set up dev $WIREGUARD_INTERFACE; 
(
    echo "[Interface]"; echo "Address = $_WIREGUARD_CLIENT_ADDRESS"; 
    cat /etc/wireguard/wg0.conf |grep -v "\[Interface\]") > t && mv -f t /etc/wireguard/wg0.conf;
    chmod -R 600 /etc/wireguard;
    chown -R root:root /etc/wireguard;
    wg-quick down $WIREGUARD_INTERFACE; 
    wg-quick up $WIREGUARD_INTERFACE; 
iptables -I INPUT -i wg0 -s 10.14.0.2 -j ACCEPT
iptables -I INPUT -i wg0 -s 10.14.0.1 -j ACCEPT
wg-quick down wg0;
systemctl enable wg-quick@wg0;
systemctl restart wg-quick@wg0;
#systemctl status wg-quick@wg0;
timeout 10 curl -4s https://ifconfig.me;echo;
'|base64 -w0)
GET_WIREGUARD_PUBLIC_KEY_CMD="wg show wg0 public-key"
GET_WIREGUARD_PORT_CMD="wg show wg0 listen-port"
GET_WIREGUARD_INTERFACES_CMD="wg show wg0 interfaces"
GET_CLIENT_IP_SUFFIXES_IN_USE_CMD="echo \"$GET_CLIENT_IP_SUFFIXES_IN_USE_CMD_ENCODED\"|base64 -d > script.sh && bash -ex script.sh"
SETUP_WIREGUARD_CLIENT_CMD="echo \"$SETUP_WIREGUARD_CLIENT_CMD_ENCODED\"|base64 -d > script.sh && bash -x script.sh"
GET_WIREGUARD_SERVER_IP_CMD="grep ^Address $WIREGUARD_CONFIG |grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'"
#GET_WIREGUARD_SERVER_IP_CMD="ifconfig wg0|grep inet|grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'|grep ^10.14.|head -n 1'"
SAVE_RUNNING_CONFIG_TO_WIREGUARD_CONFIG='wg addconf wg0 \<(wg-quick strip wg0)'
SUFFIXES_IN_USE_FILE=`mktemp`
IPS_IN_USE_FILE=`mktemp`
SERVER_PUBLIC_KEY_FILE=`mktemp`
SERVER_IP_FILE=`mktemp`
GET_RANDOM_CLIENT_IP_SUFFIX(){
    echo $(( ( RANDOM % $CLIENT_IP_SUFFIX_MAX )  + $CLIENT_IP_SUFFIX_MIN ))
}


#echo working w key
#echo "$_SECRET_KEY"
#echo "$_SECRET_PUBLIC"
#exit

command ssh $SSH_OPTS root@vpnservice.company "sh -c \"$GET_CLIENT_IP_SUFFIXES_IN_USE_CMD\"" > $SUFFIXES_IN_USE_FILE
command ssh $SSH_OPTS root@vpnservice.company "sh -c \"cat $PUBLIC_KEY_PATH\"" > $SERVER_PUBLIC_KEY_FILE
command ssh $SSH_OPTS root@vpnservice.company "$GET_WIREGUARD_SERVER_IP_CMD" > $SERVER_IP_FILE

WIREGUARD_SERVER_IP="$(cat $SERVER_IP_FILE)"
_WIREGUARD_SERVER_PUBLIC_KEY="$(cat $SERVER_PUBLIC_KEY_FILE)"
[[ "$DEBUG_MODE" == "1" ]] && echo "There are $(cat $SUFFIXES_IN_USE_FILE|wc -l|cut -d' ' -f1) IP Suffixes in use in subnet ${_SUBNET}"

(
      while IFS= read -r SUFFIX; do
         SUFFIX="$(echo $SUFFIX|sed 's/[[:space:]]//g'|head -n1)"
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

#echo _WIREGUARD_CLIENT_ADDRESS=$_WIREGUARD_CLIENT_ADDRESS
#echo Found Client Address ${_WIREGUARD_CLIENT_ADDRESS}

command ssh $SSH_OPTS $VM "sh -c \"rm -rf $INSTALL_VM_PATH 2>/dev/null; mkdir -p $INSTALL_VM_PATH 2>/dev/null; dnf -y install $VM_PACKAGES >/dev/null \""
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

#echo -e "\nSETUP_CLIENT_ON_SERVER_CMD=\n   $SETUP_CLIENT_ON_SERVER_CMD\n"

command ssh $SSH_OPTS root@vpnservice.company "sh -c \"$SETUP_CLIENT_ON_SERVER_CMD\""
exit_code=$?
#echo SETUP_CLIENT_ON_SERVER_CMD exit_code=$exit_code



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

command rsync $RSYNC_OPTS files/csf_postd_wireguard.sh $VM:/usr/local/include/csf/post.d/
command rsync $RSYNC_OPTS files/extrace.service $VM:/etc/systemd/system/.
command rsync $RSYNC_OPTS files/node-extrace.service $VM:/etc/systemd/system/.
command rsync $RSYNC_OPTS files/extrace files/pwait $VM:/usr/bin/.


set +e
command ssh $SSH_OPTS $VM "systemctl disable extrace; systemctl stop extrace; systemctl status extrace"
if [[ "$NODE_EXTRACE_ENABLED" == "1" ]]; then
    command ssh $SSH_OPTS $VM "systemctl enable node-extrace; systemctl start node-extrace; systemctl status node-extrace"
else
    command ssh $SSH_OPTS $VM "systemctl disable node-extrace; systemctl stop node-extrace; systemctl status node-extrace"
fi
set -e


command rsync $RSYNC_OPTS files/csf_postd_wireguard.sh $VM:/usr/local/include/csf/post.d/
command rsync $RSYNC_OPTS $CLIENT_SETUP_VARS_FILE $VM:/root/vars.sh
#echo -e "\nSETUP_WIREGUARD_CLIENT_CMD=\n   $SETUP_WIREGUARD_CLIENT_CMD\n"
command ssh $SSH_OPTS $VM "$SETUP_WIREGUARD_CLIENT_CMD"
exit_code=$?
#echo SETUP_WIREGUARD_CLIENT_CMD exit_code=$exit_code


VM_DNS_USER=whmcs
VM_DNS_SERVER=web1.vpnservice.company
VM_DNS_DOMAIN=vpnservice.company
VM_DNS_TTL=3600
VM_DNS_NAME="$VM"
VM_DNS_DOMAIN_ID=1052503
VM_DNS_IP="$_WIREGUARD_CLIENT_ADDRESS"


echo Disabling Root Login and creating service account
DISABLE_ROOT_CMD="ssh -tt $SSH_OPTS $VM_DNS_USER@$VM_DNS_SERVER \"\
    /home/whmcs/public_html/whmcs/modules/addons/vpntech/bin/disableRootLogin.sh $_WIREGUARD_CLIENT_ADDRESS\""

eval $DISABLE_ROOT_CMD

DNS_CMD="ssh -tt $SSH_OPTS $VM_DNS_USER@$VM_DNS_SERVER \"linode-cli domains records-create \
        --name $VM_DNS_NAME \
        --target $VM_DNS_IP \
        --type A \
        --ttl_sec $VM_DNS_TTL \
        $VM_DNS_DOMAIN_ID\""

eval $DNS_CMD

exit


ADD_VPN_NODE_TIMEOUT=60
_ADD_VPN_NODE_CMD="SKIP_CREATE_VIDEO=1 SKIP_DNS_CHECK=1 /home/whmcs/public_html/whmcs/modules/addons/vpntech/bin/createServer.sh ${VM}.$VM_DNS_DOMAIN $_WIREGUARD_CLIENT_ADDRESS"

set +e
ADD_VPN_NODE_CMD="timeout $ADD_VPN_NODE_TIMEOUT ssh -tt $SSH_OPTS $VM_DNS_USER@$VM_DNS_SERVER \"$_ADD_VPN_NODE_CMD\""
eval $ADD_VPN_NODE_CMD
exit_code=$?
echo ADD_VPN_NODE_CMD exit_code=$exit_code
set -e


echo OK
exit 0
