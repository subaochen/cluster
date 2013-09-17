#! /bin/sh
#
# set up director
# 适用于Debian 7.1，网络架构如下图所示：
# 
#                        ________
#                       |        |
#                       | client |
#                       |________|
#                       CIP=192.168.1.100
#                            |
#                            |
#             ___________    |    ___________
#            |           |   |   |           |   VIP=192.168.1.250 (eth1)
#            | director1 |---|---| director2 |   NATGW=172.16.76.250 (eth0:0)
#            |___________|   |   |___________|   DIP=172.16.76.128/129 (eth0)
#                            |    
#                            |
#          ------------------------------------
#          |                 |                 |
#          |                 |                 |
#   RIP1=172.16.76.130   RIP2=172.16.76.131  RIP3=172.16.76.132 (all eth0)
#    _____________      _____________     _____________
#   |             |    |             |   |             |
#   | realserver  |    | realserver  |   | realserver  |
#   |_____________|    |_____________|   |_____________|
#
# 注意事项：
# 
# 1. 本脚本假设调度服务器的eth0为内网，eth1为外网，并分别设置好IP地址
# 2. 使用本脚本前需要设置好hosts：director1/director2/rs1/rs2
#

if [ $# -ne 5 ]
then
    echo "usage:"
    echo "director.sh this_host this_host_ip other_host other_host_ip VIP"
    exit 1
fi
export LANG=C
export LC_ALL=C

THIS_HOST=$1
THIS_HOST_IP=$2
OTHER_HOST=$3
OTHER_HOST_IP=$4
VIP=$5

# 使能包转发
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# 使用更合适的软件源
if [ -f /etc/apt/sources.list ]; then 
    mv /etc/apt/sources.list /etc/apt/sources.list.bak
fi
cat > /etc/apt/sources.list << SOURCES
deb http://mirrors.163.com/debian wheezy main non-free contrib
deb http://mirrors.163.com/debian wheezy-proposed-updates main contrib non-free
deb-src http://mirrors.163.com/debian wheezy main non-free contrib
deb-src http://mirrors.163.com/debian wheezy-proposed-updates main contrib non-free

deb http://mirrors.163.com/debian-security wheezy/updates main contrib non-free 
deb-src http://mirrors.163.com/debian-security wheezy/updates main contrib non-free 

deb http://http.us.debian.org/debian wheezy main contrib non-free
#deb http://non-us.debian.org/debian-non-US wheezy/non-US main contrib non-free
deb http://security.debian.org wheezy/updates main contrib non-free
SOURCES

# 安装必要的软件包
aptitude update
aptitude install -y heartbeat ldirectord ipvsadm nginx openssh-server vim ntpdate ntp rsync

# 时间同步
service ntp stop
ntpdate cn.pool.ntp.org
service ntp start

# 构造集群配置文件
if [ -f /etc/ha.d/authkeys ]; then
    mv /etc/ha.d/authkeys /etc/ha.d/authkeys.bak
fi
cat > /etc/ha.d/authkeys << AUTHKEYS
auth 1
1 crc
AUTHKEYS

chmod 600 /etc/ha.d/authkeys

if [ -f /etc/ha.d/ha.cf ]; then
    mv /etc/ha.d/ha.cf /etc/ha.d/ha.cf.bak
fi
cat > /etc/ha.d/ha.cf << HA.CF
use_logd yes
keepalive 2
deadtime 30
warntime 10
initdead 120
udpport 694
bcast   eth0            # Linux
ucast eth0 $OTHER_HOST_IP
auto_failback on
node   $THIS_HOST $OTHER_HOST 
#ping 172.16.76.1
crm yes

HA.CF

if [ -f /etc/ldirectord.cf ]; then
    mv /etc/ldirectord.cf /etc/ldirectord.cf.bak
fi
cat > /etc/ldirectord.cf << LDIRECTORD.CF
checktimeout=3
checkinterval=1
autoreload=yes
logfile="/var/log/ldirectord.log"
quiescent=yes

virtual=$VIP:80
        real=rs1:80 masq 10
        real=rs2:80 masq 10
        fallback=127.0.0.1:80 masq
        service=http
        request=".lvs.html"
        receive="Test Page"
        scheduler=wlc # rr
        #persistent=600
        #netmask=255.255.255.255
        protocol=tcp
        checktype=negotiate
        checkport=80

LDIRECTORD.CF

cat "1" > /proc/sys/kernel/core_uses_pid
service heartbeat reload

# 代理，real server能够链接外网
