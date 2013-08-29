#! /bin/sh
#
# set up database cluster, base on postgresql 9.1/pgpool 3.3
# 适用于Debian 7.1，网络架构如下图所示：
# 
#                  ____________________
#                 |                    |
#                 | client/real server |
#                 |____________________|
#                    CIP=172.16.76.132
#                            |
#                            |
#             ___________    |    ___________
#            |           |   |   |           |   VIP=172.16.76.251 (eth0)
#            |    db1    |---|---|    db2    |   
#            |___________|       |___________|   DIP=172.16.76.128/129 (eth0)
#                                
#                            
# 注意事项：
# 1. 首先设置好服务器的IP地址等 
# 2. 使用本脚本前需要设置好hosts：db1/db2
# 3. pgpool 3.3需要事先手工安装好 aptitude install gcc make postgresql-server-dev-9.1; ./configure; make; make install
# 4. 设置好db1/db2的无密码访问
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
aptitude install -y openssh-server vim ntpdate ntp rsync postgresql-9.1

# 时间同步
service ntp stop
ntpdate cn.pool.ntp.org
service ntp start

# 构造集群配置文件
# TODO 如何根据服务器配置修改postgresql.conf中的参数？
if [ -f /etc/postgresql/9.1/main/pg_hba.conf ]; then
    mv /etc/postgresql/9.1/main/pg_hba.conf /etc/postgresql/9.1/main/pg_hba.conf.bak
fi
cp -f pg_hba.conf /etc/postgresql/9.1/main/pg_hba.conf

if [ -f /etc/postgresql/9.1/main/postgresql.conf ]; then
    mv /etc/postgresql/9.1/main/postgresql.conf /etc/postgresql/9.1/main/ppostgresql.conf.bak
fi
cp -f postgresql.conf /etc/postgresql/9.1/main/postgresql.conf

cp -f pgpool_remote_start basebackup.sh recovery.conf /var/lib/postgresql/9.1/main
mv /var/lib/postgresql/9.1/main/recovery.conf /var/lib/postgresql/9.1/main/recovery.done
mkdir /var/lib/postgresql/9.1/main/archive
chown postgres.postgres /var/lib/postgresql/9.1/main/recovery.done
chown postgres.postgres /var/lib/postgresql/9.1/main/pgpool_remote_start
chown postgres.postgres /var/lib/postgresql/9.1/main/basebackup.sh
chown postgres.postgres /var/lib/postgresql/9.1/main/archive

service postgresql restart

# 配置pgpool
# TODO 对端参数的设置？
cp -f pcp.conf pgpool.conf /usr/local/etc/
cp -f pgpool_default /etc/default/pgpool/
cp -f pgpool2 /etc/init.d/
update-rc.d pgpool2 defaults

service pgpool2 start
