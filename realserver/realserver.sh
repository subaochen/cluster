#! /bin/sh
#
# 建立realserver
# 首先要设置正确的IP地址，尤其是默认网关要设置正确

if [ $# -ne 0 ]
then
    echo "usage:"
    echo "realserver.sh"
    exit 1
fi

# 
# 使用更合适的软件源
if [ -e /etc/apt/sources.list ]; then 
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
aptitude install -y nginx openssh-server vim ntpdate ntp rsync

# 时间同步
service ntp stop
ntpdate cn.pool.ntp.org
service ntp start


# 安装和配置jdk
cp rsapps/jdk-6u38-linux-x64.bin /opt
cd /opt
./jdk-6u38-linux-x64.bin
ln -s jdk1.6.0_38 jdk
rm -f jdk-6u38-linux-x64.bin
export JAVA_HOME=/opt/jdk

# 安装和配置jboss
cd -
cp rsapps/jboss-as-7.1.1.Final.tar.gz /opt
cd /opt
tar xzvf jboss-as-7.1.1.Final.tar.gz
ln -s jboss-as-7.1.1.Final jboss
export JBOSS_HOME=/opt/jboss

# jboss自启动
adduser --system --group --no-create-home --home $JBOSS_HOME --disabled-login jboss
mkdir $JBOSS_HOME/standalone/data $JBOSS_HOME/standalone/log
chown jboss:jboss $JBOSS_HOME

cat > /etc/default/jboss7 << JBOSS_DEFAULT

# General configuration for the init.d scripts,
# not necessarily for JBoss AS itself.

# Location of JDK
JAVA_HOME=/opt/jdk

# Location of JBoss
JBOSS_HOME=/opt/jboss

# The username who should own the process.
JBOSS_USER=jboss

# The amount of time to wait for startup
# STARTUP_WAIT=30

# The amount of time to wait for shutdown
# SHUTDOWN_WAIT=30

JBOSS_DEFAULT

cat > /etc/init.d/jboss7 << JBOSS

#!/bin/sh
#
# /etc/init.d/jboss7 -- startup script for the JBoss 7 Application Server
#
# Written by Jorge Solorzano <jorsol@ubuntu.org.ni>.
#
### BEGIN INIT INFO
# Provides:          jboss7
# Required-Start:    $remote_fs $network
# Required-Stop:     $remote_fs $network
# Should-Start:      $named
# Should-Stop:       $named
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: JBoss AS 7
# Description:       Start-Stop the JBoss Application Server 7.
### END INIT INFO

NAME=jboss7
DESC="JBoss Application Server 7"
DEFAULT=/etc/default/$NAME

# Check privileges
if [ `id -u` -ne 0 ]; then
        echo "You need root privileges to run this script"
        exit 1
fi

# Make sure jboss is started with system locale
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG
fi

. /lib/lsb/init-functions

if [ -r /etc/default/rcS ]; then
    . /etc/default/rcS
fi

# Overwrite settings from default file
if [ -f "$DEFAULT" ]; then
    . "$DEFAULT"
fi

# Location of java
if [ -z "$JAVA_HOME" ]; then
    JAVA_HOME=/opt/jdk
fi
export JAVA_HOME

# Check if java is installed
if [ ! -f "$JAVA_HOME/bin/java" ]; then
    log_failure_msg "Java is not installed in $JAVA_HOME"
    exit 1
fi

# Location of jboss
if [ -z "$JBOSS_HOME" ]; then
    JBOSS_HOME=/opt/jboss
fi
export JBOSS_HOME

# Check if jboss is installed
if [ ! -f "$JBOSS_HOME/jboss-modules.jar" ]; then
    log_failure_msg "$NAME is not installed in $JBOSS_HOME"
    exit 1
fi

# Run as jboss user
if [ -z "$JBOSS_USER" ]; then
    JBOSS_USER=jboss
fi

# Check jboss user
id $JBOSS_USER > /dev/null 2>&1
if [ $? -ne 0 -o -z "$JBOSS_USER" ]; then
    log_failure_msg "User $JBOSS_USER does not exist..."
    log_end_msg 1
    exit 1
fi

# Check startup file
JBOSS_SCRIPT=$JBOSS_HOME/bin/standalone.sh
if [ ! -x $JBOSS_SCRIPT ]; then
    log_failure_msg "$JBOSS_SCRIPT is not an executable!"
    exit 1
fi

# Check shutdown file
JBOSS_SH_SHUTDOWN=$JBOSS_HOME/bin/jboss-cli.sh
if [ ! -x $JBOSS_SH_SHUTDOWN ]; then
    log_failure_msg "$JBOSS_SH_SHUTDOWN is not an executable!"
    exit 1
fi

# The amount of time to wait for startup
if [ -z "$STARTUP_WAIT" ]; then
  STARTUP_WAIT=30
fi

# The amount of time to wait for shutdown
if [ -z "$SHUTDOWN_WAIT" ]; then
  SHUTDOWN_WAIT=30
fi

# Location to keep the console log
export JBOSS_CONSOLE_LOG=/var/log/$NAME/console.log
# Location to set the pid file
export JBOSS_PIDFILE=/run/$NAME/$NAME.pid
# Launch jboss in background
export LAUNCH_JBOSS_IN_BACKGROUND=true

# Helper function to check status of jboss service
check_status() {
    start-stop-daemon --status --name java --user $JBOSS_USER \
    --pidfile "$JBOSS_PIDFILE" >/dev/null 2>&1
    return $?
}

case "$1" in
 start)
    log_daemon_msg "Starting $DESC" "$NAME"
    check_status
    status_start=$?
    if [ $status_start -eq 3 ]; then
        mkdir -p $(dirname $JBOSS_PIDFILE)
        mkdir -p $(dirname $JBOSS_CONSOLE_LOG)
        chown $JBOSS_USER $(dirname $JBOSS_PIDFILE)
        cat /dev/null > $JBOSS_CONSOLE_LOG

        start-stop-daemon --start --user "$JBOSS_USER" \
        --chuid "$JBOSS_USER" --chdir "$JBOSS_HOME" --pidfile "$JBOSS_PIDFILE" \
        --exec "$JBOSS_SCRIPT" 2>&1 > $JBOSS_CONSOLE_LOG &

        count=0
        launched=false
        until [ $count -gt $STARTUP_WAIT ]
        do
            grep 'JBAS015874:' $JBOSS_CONSOLE_LOG > /dev/null 
            if [ $? -eq 0 ] ; then
                launched=true
                break
            fi
            sleep 1
            count=$(($count + 1));
        done

        if check_status; then
            log_end_msg 0
        else
            log_end_msg 1
        fi
    elif [ $status_start -eq 1 ]; then
        log_failure_msg "$DESC is not running but the pid file exists"
        log_end_msg 1
        exit 1
    elif [ $status_start -eq 0 ]; then
        log_success_msg "$DESC (already running)"
        log_end_msg 0
    fi
 ;;
 stop)
    check_status
    status_stop=$?
    if [ $status_stop -eq 0 ]; then
        read kpid < $JBOSS_PIDFILE
        log_daemon_msg "Stopping $DESC" "$NAME"
        start-stop-daemon --start --chuid "$JBOSS_USER" \
        --exec "$JBOSS_SH_SHUTDOWN" -- --connect --command=:shutdown \
        >/dev/null 2>&1

        if [ $? -eq 1 ]; then
            kill -15 $kpid
        fi

        count=0
        until [ $count -gt $SHUTDOWN_WAIT ]
        do
            check_status
            if [ $? -eq 3 ]; then
                break
            fi
            sleep 1
            count=$(($count + 1));
        done
        
        if [ $count -gt $SHUTDOWN_WAIT ]; then
            kill -9 $kpid
        fi
    elif [ $status_stop -eq 1 ]; then
        log_daemon_msg "$DESC is not running but the pid file exists, cleaning up"
        rm -f $JBOSS_PIDFILE
    elif [ $status_stop -eq 3 ]; then
        log_daemon_msg "$DESC is not running"
    fi

    log_end_msg 0
 ;;
 restart|reload|force-reload)
    check_status
    status_restart=$?
    if [ $status_restart -eq 0 ]; then
        $0 stop
    fi
    $0 start
 ;;
 status)
    check_status
    status=$?
    if [ $status -eq 0 ]; then
        log_success_msg "$DESC is running with pid `cat $JBOSS_PIDFILE`"
        exit 0
    elif [ $status -eq 1 ]; then
        log_success_msg "$DESC is not running and the pid file exists"
        exit 1
    elif [ $status -eq 3 ]; then
        log_success_msg "$DESC is not running"
        exit 3
    else
        log_success_msg "Unable to determine $NAME status"
        exit 4
    fi
 ;;
 *)
 log_action_msg "Usage: $0 {start|stop|restart|status}"
 exit 2
 ;;
esac

exit 0

JBOSS

chmod +x /etc/init.d/jboss7

update-rc.d jboss7 defaults

# 调整jboss运行参数
# 端口/内存使用等
# 屏蔽默认欢迎页面

# 设置部署扫描器的超时时间，防止部署失败

# 调整jboss内存参数


service jboss7 start

# 配置ngnix
if [ -f /etc/nginx/proxy_params ]; then
    mv /etc/nginx/proxy_params /etc/nginx/proxy_params.bak
fi

echo > /etc/nginx/proxy/params << PROXY_PARAMS
proxy_set_header   Host $host;
proxy_set_header   X-Real-IP $remote_addr;
proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header   X-Forwarded-Proto $scheme;

client_max_body_size       100m;
client_body_buffer_size    128k;

proxy_connect_timeout      90;
proxy_send_timeout         90;
proxy_read_timeout         90;

proxy_buffer_size          4k;
proxy_buffers              432k;
proxy_busy_buffers_size    64k;
proxy_temp_file_write_size 64k;
PROXY_PARAMS

if [ -f /etc/nginx/nginx.conf ]; then
   mv /etc/nginx/nginx.conf /etc/nginx.conf.bak
fi

echo > /etc/nginx/nginx.conf << NGINX.CONF
user www-data;
worker_processes  4;
pid        /var/run/nginx.pid;

events {
    use epoll;
    worker_connections  2048;
    # multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    access_log    /var/log/nginx/access.log;
    error_log     /var/log/nginx/error.log;

    sendfile        on;
    tcp_nopush     on;
    tcp_nodelay        on;
    keepalive_timeout  65;

    upstream jboss {
        server 127.0.0.1:8080 weight=10;
    }

    gzip  on;
    gzip_disable "MSIE [1-6]\.(?!.*SV1)";

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}

NGINX.CONF

if [ -f /etc/nginx/sites-available/default ]; then
    mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
fi

echo > /etc/nginx/sites-available/default << DEFAULT_SITE
server {
    listen   80; ## listen for ipv4
    listen   [::]:80 default ipv6only=on; ## listen for ipv6

    server_name  localhost;
    client_max_body_size       100m;

    root /var/www;

    # for images
    location /imgs {
        index index.html;
    }

    # for javascript
    location /js {
        index index.html;
    }

    location / {
        proxy_pass http://jboss;
    }
    
}

DEFAULT_SITE

# 部署应用
