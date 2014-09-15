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
# 3. pgpool 3.3需要事先手工安装好。安装步骤如下：
#   3.1 aptitude install gcc make postgresql-server-dev-9.1
#   3.2 下载pgpool 3.3 II的最新版本，执行./configure;make;make install 
#   3.3 That's ALL! 其余配置由下面脚本完成
# 4. 服务器之间需要设置好无密码访问
#

if [ $# -ne 6 ]
then
    echo "usage:"
    echo "dbsetup.sh master_host master_host_ip slave_host slaver_host_ip VIP master[1|0]"
    exit 1
fi
export LANG=C
export LC_ALL=C

MASTER_HOST=$1
MASTER_HOST_IP=$2
SLAVE_HOST=$3
SLAVE_HOST_IP=$4
VIP=$5
MASTER=$6
RECOVERY_CONF="recovery.conf"
# 初始情况下conn host为slave host，当配置slave host的时候需要设置为master host
CONN_HOST=$SLAVE_HOST
TRIGGER_FILE="/tmp/pgsql.trigger.file"

# 删除可能的遗留文件
rm -f $TRIGGER_FILE
rm -f /var/lib/postgresql/9.1/main/recovery.*

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
aptitude install -y openssh-server vim ntpdate ntp rsync postgresql-9.1 arping

if [ $MASTER -eq 0 ]; then
    service postgresql stop
fi


# 时间同步
service ntp stop
ntpdate cn.pool.ntp.org
service ntp start

# 构造集群配置文件
# TODO 如何根据服务器配置修改postgresql.conf中的参数？
# pg_hba.conf需要根据网络灵活设置

# 如果已经有存在的postgresql则首先停止运行
service postgresql stop

if [ -f /etc/postgresql/9.1/main/pg_hba.conf ]; then
    mv /etc/postgresql/9.1/main/pg_hba.conf /etc/postgresql/9.1/main/pg_hba.conf.bak
fi

cat > /etc/postgresql/9.1/main/pg_hba.conf << PGHBA
local   all             postgres                                trust
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             $VIP/32                 trust
host    all             all             $MASTER_HOST_IP/32        trust
host    all             all             $SLAVE_HOST_IP/32       trust
local   replication     postgres                                trust
host    replication     postgres        127.0.0.1/32            trust
host    replication     postgres        ::1/128                 trust
host    replication     postgres        ::1/128                 trust
host    replication     postgres        $VIP/32                 trust
host    replication     postgres        $MASTER_HOST_IP/32        trust
host    replication     postgres        $SLAVE_HOST_IP/32       trust

PGHBA

if [ -f /usr/local/bin/failover_stream.sh ]; then
    mv /usr/local/bin/failover_stream.sh /usr/local/bin/failover_stream.sh.bak
fi
cp -f failover_stream.sh /usr/local/bin/

if [ -f /etc/postgresql/9.1/main/postgresql.conf ]; then
    mv /etc/postgresql/9.1/main/postgresql.conf /etc/postgresql/9.1/main/ppostgresql.conf.bak
fi
cp -f postgresql.conf /etc/postgresql/9.1/main/postgresql.conf

# 如果是从服务器则需要根据master建立数据库基础数据
if [ $MASTER -eq 0 ]; then
    rm -rf /var/lib/postgresql/9.1/main/*
    su - postgres -c "/usr/lib/postgresql/9.1/bin/pg_basebackup -w -Fp -x -v -D /var/lib/postgresql/9.1/main -h $MASTER_HOST"
fi

cp -f pgpool_remote_start basebackup.sh  /var/lib/postgresql/9.1/main

if [ ! -d /var/lib/postgresql/9.1/main/archive ]; then
    mkdir /var/lib/postgresql/9.1/main/archive
fi
chown postgres.postgres /var/lib/postgresql/9.1/main/pgpool_remote_start
chown postgres.postgres /var/lib/postgresql/9.1/main/basebackup.sh
chown postgres.postgres /var/lib/postgresql/9.1/main/archive
chown postgres.postgres /etc/postgresql/9.1/main/pg_hba.conf
chown postgres.postgres /etc/postgresql/9.1/main/postgresql.conf

# 根据master/slave具体情况重新写recovery.conf文件，主要是conninfo中的dbname
rm -f /var/lib/postgresql/9.1/main/recovery.*
if [ $MASTER -eq 1 ]; then
    RECOVERY_CONF="recovery.done"
fi

if [ $MASTER -eq 0 ]; then
    CONN_HOST=$MASTER_HOST
fi

cat > /var/lib/postgresql/9.1/main/${RECOVERY_CONF} << RECOVERY.CONF
standby_mode=on
primary_conninfo='host=$CONN_HOST'
trigger_file='$TRIGGER_FILE'
recovery_target_timeline='latest'
RECOVERY.CONF

chown postgres.postgres /var/lib/postgresql/9.1/main/recovery.*

if [ $MASTER -eq 0 ]; then
    rm -f /var/lib/postgresql/9.1/main/server.*
    ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem /var/lib/postgresql/9.1/main/server.crt
    ln -s /etc/ssl/private/ssl-cert-snakeoil.key /var/lib/postgresql/9.1/main/server.key
fi

service postgresql start

# 配置pgpool
# TODO 对端参数的设置？
if [ -f /usr/local/etc/pgpool.conf ]; then
    mv /usr/local/etc/pgpool.conf /usr/local/etc/pgpool.conf.bak;
fi

WD_HOST=$MASTER_HOST
WD_DEST=$SLAVE_HOST
if [ $MASTER -eq 0 ]; then
    WD_HOST=$SLAVE_HOST
    WD_DEST=$MASTER_HOST
fi

cat > /usr/local/etc/pgpool.conf << PGPOOL.CONF

listen_addresses = '*'
port = 9999
socket_dir = '/var/run/postgresql'
pcp_port = 9898
pcp_socket_dir = '/var/run/postgresql'
backend_hostname0 = '$MASTER_HOST'
backend_port0 = 5432
backend_weight0 = 1
backend_data_directory0 = '/var/lib/postgresql/9.1/main'
backend_flag0 = 'ALLOW_TO_FAILOVER'
backend_hostname1 = '$SLAVE_HOST'
backend_port1 = 5432
backend_weight1 = 1
backend_data_directory1 = '/var/lib/postgresql/9.1/main'
backend_flag1 = 'ALLOW_TO_FAILOVER'


enable_pool_hba = off
#pool_passwd = 'pool_passwd'
pool_passwd = ''
authentication_timeout = 60

ssl = off
#ssl_key = './server.key'
#ssl_cert = './server.cert'
#ssl_ca_cert = ''
#ssl_ca_cert_dir = ''


num_init_children = 32
max_pool = 4
child_life_time = 300
child_max_connections = 0
connection_life_time = 0
client_idle_limit = 0

log_destination = 'stderr'

# - What to log -

print_timestamp = on
log_connections = off
log_hostname = off
log_statement = off
log_per_node_statement = on
log_standby_delay = 'none'

syslog_facility = 'LOCAL0'
syslog_ident = 'pgpool'
# - Debug -
debug_level = 10


#------------------------------------------------------------------------------
# FILE LOCATIONS
#------------------------------------------------------------------------------
pid_file_name = '/var/run/postgresql/pgpool.pid'
logdir = '/var/run/postgresql'

#------------------------------------------------------------------------------
# CONNECTION POOLING
#------------------------------------------------------------------------------

connection_cache = on
reset_query_list = 'ABORT; DISCARD ALL'
#reset_query_list = 'ABORT; RESET ALL; SET SESSION AUTHORIZATION DEFAULT'

#------------------------------------------------------------------------------
# REPLICATION MODE
#------------------------------------------------------------------------------

replication_mode = off
replicate_select = off
insert_lock = off
lobj_lock_table = ''

# - Degenerate handling -

replication_stop_on_mismatch = off
failover_if_affected_tuples_mismatch = off

#------------------------------------------------------------------------------
# LOAD BALANCING MODE
#------------------------------------------------------------------------------

load_balance_mode = on
ignore_leading_white_space = on
white_function_list = ''
black_function_list = 'currval,lastval,nextval,setval'


#------------------------------------------------------------------------------
# MASTER/SLAVE MODE
#------------------------------------------------------------------------------

master_slave_mode = on
master_slave_sub_mode = 'stream'
sr_check_period = 10
sr_check_user = 'postgres'
sr_check_password = '111111'
delay_threshold = 0

# - Special commands -
follow_master_command = ''

#------------------------------------------------------------------------------
# PARALLEL MODE
#------------------------------------------------------------------------------

parallel_mode = off
pgpool2_hostname = ''

# - System DB info -
#system_db_hostname  = 'localhost'
#system_db_port = 5432
#system_db_dbname = 'pgpool'
#system_db_schema = 'pgpool_catalog'
#system_db_user = 'pgpool'
#system_db_password = ''


#------------------------------------------------------------------------------
# HEALTH CHECK
#------------------------------------------------------------------------------

health_check_period = 30
health_check_timeout = 20
health_check_user = 'postgres'
health_check_password = '111111'
health_check_max_retries = 0
health_check_retry_delay = 1

#------------------------------------------------------------------------------
# FAILOVER AND FAILBACK
#------------------------------------------------------------------------------

failover_command = '/usr/local/bin/failover_stream.sh %d %H $TRIGGER_FILE'
fail_over_on_backend_error = on
search_primary_node_timeout = 10

#------------------------------------------------------------------------------
# ONLINE RECOVERV
#----------------------------------------------------------------------------

recovery_user = 'postgres'
recovery_password = '111111'
recovery_1st_stage_command = 'basebackup.sh'
recovery_2nd_stage_command = ''
recovery_timeout = 90
client_idle_limit_in_recovery = 0

#------------------------------------------------------------------------------
# WATCHDOG
#------------------------------------------------------------------------------

# - Enabling -

use_watchdog = on
trusted_servers = ''
ping_path = '/bin'
wd_hostname = '$WD_HOST'
wd_port = 9000
wd_authkey = ''
delegate_IP = '$VIP'
ifconfig_path = '/sbin'
if_up_cmd = 'ifconfig eth0:0 inet \$_IP_\$ netmask 255.255.255.0'
if_down_cmd = 'ifconfig eth0:0 down'
arping_path = '/usr/sbin'           # arping command path
arping_cmd = 'arping -U \$_IP_\$ -w 1'
# - Behaivor on escalation Setting -

clear_memqcache_on_escalation = on
wd_escalation_command = ''

# - Lifecheck Setting - 

# -- common --
wd_lifecheck_method = 'heartbeat'
wd_interval = 10

# -- heartbeat mode --
wd_heartbeat_port = 9694
wd_heartbeat_keepalive = 2
wd_heartbeat_deadtime = 30
heartbeat_destination0 = '$MASTER_HOST'
heartbeat_destination_port0 = 9694 
heartbeat_device0 = 'eth0'
heartbeat_destination1 = '$SLAVE_HOST'
heartbeat_destination_port1 = 9694
heartbeat_device1 = 'eth0'

# -- query mode --

wd_life_point = 3
wd_lifecheck_query = 'SELECT 1'
wd_lifecheck_dbname = 'template1'
wd_lifecheck_user = 'postgres'
wd_lifecheck_password = '111111'

# - Other pgpool Connection Settings -
other_pgpool_hostname0 = '$WD_DEST'
other_pgpool_port0 = 9999
other_wd_port0 = 9000


#------------------------------------------------------------------------------
# OTHERS
#------------------------------------------------------------------------------
relcache_expire = 0
relcache_size = 256
check_temp_table = on

#------------------------------------------------------------------------------
# ON MEMORY QUERY MEMORY CACHE
#------------------------------------------------------------------------------
memory_cache_enabled = off
memqcache_method = 'shmem'
memqcache_memcached_host = 'localhost'
memqcache_memcached_port = 11211
memqcache_total_size = 67108864
memqcache_max_num_cache = 1000000
memqcache_expire = 0
memqcache_auto_cache_invalidation = on
memqcache_maxcache = 409600
memqcache_cache_block_size = 1048576
memqcache_oiddir = '/var/log/pgpool/oiddir'
white_memqcache_table_list = ''
black_memqcache_table_list = ''

PGPOOL.CONF

cp -f pcp.conf /usr/local/etc/
cp -f pgpool_default /etc/default/pgpool
cp -f pgpool2 /etc/init.d/
chmod +x /etc/init.d/pgpool2
chmod u+s /sbin/ifconfig /usr/sbin/arping
update-rc.d pgpool2 defaults

service pgpool2 start

echo "waiting about 60s for pgpool up..."
sleep 60s

if [ $MASTER -eq 1 ]; then
    pcp_attach_node -d 5 localhost 9898 postgres postgres 0
    echo "pgpool II slave server added"
fi

if [ $MASTER -eq 0 ]; then
    pcp_attach_node -d 5 localhost 9898 postgres postgres 1
    echo "pgpool II master server added"
fi

psql -U postgres -p 9999 -h $VIP -c "show pool_nodes"

# pgpool 的调试方法
# pgpool -n可以在终端打印出调试信息 
