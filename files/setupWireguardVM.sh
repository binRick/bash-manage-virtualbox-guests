#!/bin/bash
#wget http://download.virtualbox.org/virtualbox/6.0.12/VBoxGuestAdditions_6.0.12.iso
if [[ "$SUBNET" == "" ]];  then echo Invalid SUBNET; exit 1; fi
if [[ "$WIREGUARD_CLIENT_ADDRESS" == "" ]];  then echo Invalid WIREGUARD_CLIENT_ADDRESS; exit 1; fi
if [[ "$_WIREGUARD_CLIENT_ROUTES" == "" ]];  then echo Invalid WIREGUARD_CLIENT_ROUTES; exit 1; fi
if [[ "$WIREGUARD_SERVER_ENDPOINT" == "" ]];  then echo Invalid WIREGUARD_SERVER_ENDPOINT; exit 1; fi
if [[ "$WIREGUARD_SERVER_PUBLIC_KEY" == "" ]];  then echo Invalid WIREGUARD_SERVER_PUBLIC_KEY; exit 1; fi
if [[ "$PUBLIC_KEY_PATH" == "" ]];  then echo Invalid PUBLIC_KEY_PATH; exit 1; fi

mkdir -p /usr/local/include/csf/post.d

(
    time dnf -y install tar bzip2 kernel-devel-$(uname -r) kernel-headers perl gcc make elfutils-libelf-devel epel-release net-tools rsync sysstat mlocate 
    sudo curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo
    time dnf -y install wireguard-dkms wireguard-tools
) >/dev/null

set -e
(
 modprobe wireguard
 lsmod|grep wireguard
 mkdir -p /etc/wireguard
) >/dev/null


echo c3NoLXJzYSBBQUFBQjNOemFDMXljMkVBQUFBREFRQUJBQUFCQVFDb2FnbWc1TmFsQTZ2Z1ppL1hNR1ZhWUpsc0tRb0hwNkJDTVJMTXBieVhUeDFNczFDRENKREZCdlNERjc1SCsvdkhRa2dZTWNNQ0pITEprWEMycHhlSkZjcjI3VVhzQUYvYlRWM240WmtIRkwxQUlOTUNMMTEyUjRrWGxaVWFUdkRaeWhNZ2ZialJvT0thd2g4VVFXQ1I1ZTJaZmdXVDJnczJ0ZmxIbFVrZmtBcEdreWhwTmV4L0Y1SGNZVXM1RHp4cmRRc3RsUTF5UmpFMXRrbkVzTTZPMXI3dmc2bm41d2l2ajNlOGxGRHlWOGF5ODRJcytvNHUzeXhWenJaVWtlWUs0SkEzR1cwUzBSUlJPb2lWY1R6SWZwb3hSYTlFOWZSZFhNVlAyekdnVWdodzZ5U0JDVlhNenAreDNyZmRzd0ZBKzYydHhvck52OVBhd3lDcVo4OGwgd2htY3NAd2ViMS52cG5zZXJ2aWNlLmNvbXBhbnkK|base64 -d >> /root/.ssh/authorized_keys && chmod 600 -R /root/.ssh

cd /etc/wireguard
(command wg genkey | command tee privatekey | command wg pubkey > $PUBLIC_KEY_PATH) >/dev/null

PUB="$(cat $PUBLIC_KEY_PATH)"
PRIV="$(cat privatekey)"

echo $WIREGUARD_CLIENT_ADDRESS
exit 0

cat << EOF > wg0.conf
[Interface]
EOF
echo "Address = ${WIREGUARD_CLIENT_ADDRESS}/32" >> wg0.conf
cat << EOF >> wg0.conf
PrivateKey = $PRIV

[Peer]
PublicKey = ${WIREGUARD_SERVER_PUBLIC_KEY}
AllowedIPs = ${_WIREGUARD_CLIENT_ROUTES}
Endpoint = $WIREGUARD_SERVER_ENDPOINT
PersistentKeepalive = 25
EOF




chmod 600 wg0.conf 
cat wg0.conf

wg-quick down wg0 2>/dev/null
wg-quick up wg0
wg


curl -Lo /usr/lib/systemd/system/wg-quick@.service https://raw.githubusercontent.com/WireGuard/WireGuard/master/src/tools/systemd/wg-quick%40.service
systemctl enable wg-quick@wg0.service
(wg-quick down wg0 ; systemctl stop wg-quick@wg0.service)2>/dev/null
systemctl start wg-quick@wg0.service
#systemctl status wg-quick@wg0.service
#timeout 5 curl -s https://ifconfig.me
#cat << _EOF > .server_include.conf
#cat << EOF >> /etc/wireguard/wg0.conf
#[Peer]
#PublicKey = $PUB
#AllowedIPs = ${WIREGUARD_CLIENT_ADDRESS}/32
#EOF
#_EOF
#chmod 600 .server_include.conf
#cat .server_include.conf
#echo 'wg addconf wg0 <(wg-quick strip wg0)'
