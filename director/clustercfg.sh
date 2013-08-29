#! /bin/sh

if [ $# -ne 2 ]
then
    echo "usage:"
    echo "clustercfg.sh VIP NATGWIP"
    exit 1
fi
export LANG=C
export LC_ALL=C

VIP=$1
NATGWIP=$2 # real server's gateway
# 配置资源
crm configure property stonith-enabled=false
crm configure property no-quorum-policy=ignore
crm configure primitive natGWIP ocf:heartbeat:IPaddr2 params ip=$NATGWIP lvs_support="true" cidr_netmask=24 nic="eth0" op monitor interval="2m" timeout="20s" op start timeout="90s" op stop timeout="100s"
crm configure primitive clusterIP ocf:heartbeat:IPaddr2 params ip=$VIP lvs_support="true" cidr_netmask=32 nic="eth1" op monitor interval="2m" timeout="20s" op start timeout="90s" op stop timeout="100s"
crm configure primitive ldirectord ocf:heartbeat:ldirectord params configfile="/etc/ldirectord.cf" op monitor interval="2m" timeout="20s" op start timeout="90s" op stop timeout="100s"
crm configure colocation clusterIP_ldirectord INFINITY:  clusterIP natGWIP  ldirectord
crm configure order order_clusterIP_ldirectord mandatory:  clusterIP natGWIP ldirectord
crm configure commit
crm status
