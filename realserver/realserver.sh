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
cp -f rsapps/jdk-6u45-linux-x64.bin /opt
cd /opt
./jdk-6u45-linux-x64.bin
if [ -h jdk ]; then
    rm jdk;
fi
ln -s jdk1.6.0_45 jdk
rm -f jdk-6u45-linux-x64.bin
export JAVA_HOME=/opt/jdk

# 安装和配置jboss
cd -
cp -f rsapps/jboss-as-7.1.1.Final.tar.gz /opt
cd /opt
if [ -d jboss-as-7.1.1.Final ]; then
    mv jboss-as-7.1.1.Final jboss-as-7.1.1.Final.bak;
fi;
tar xzvf jboss-as-7.1.1.Final.tar.gz
if [ -h jboss ]; then
    rm jboss;
fi
ln -s jboss-as-7.1.1.Final jboss
export JBOSS_HOME=/opt/jboss

# jboss自启动
adduser --system --group --no-create-home --home $JBOSS_HOME --disabled-login jboss
if [ ! -d $JBOSS_HOME/standalone/data ]; then
mkdir $JBOSS_HOME/standalone/data;
fi
if [ ! -d $JBOSS_HOME/standalone/log ]; then
mkdir $JBOSS_HOME/standalone/log;
fi
chown -R jboss:jboss jboss-as-7.1.1.Final

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

cd -
cp -f jboss7 /etc/init.d

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

cp -f proxy_params /etc/nginx/

if [ -f /etc/nginx/nginx.conf ]; then
   mv /etc/nginx/nginx.conf /etc/nginx.conf.bak
fi

cp -f nginx.conf /etc/nginx/

if [ -f /etc/nginx/sites-available/default ]; then
    mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
fi

cp -f default /etc/nginx/sites-available/

mkdir -p /var/www/lvs
echo "Test Page" >> /var/www/lvs/.lvs.html


service nginx restart

# 部署应用
