ecovery script for streaming replication.
# This script assumes that DB node 0 is primary, and 1 is standby.
#
datadir=$1
desthost=$2
destdir=$3

psql -c "SELECT pg_start_backup('Streaming Replication', true)" postgres

ssh -T $desthost rm -rf $destdir/*

/usr/bin/rsync -C -a --delete -e ssh --exclude postmaster.pid \
--exclude postmaster.opts --exclude pg_log --exclude pg_xlog \
--exclude recovery.conf $datadir/ $desthost:$destdir/

ssh -T $desthost /bin/mv $destdir/recovery.done $destdir/recovery.conf
ssh -T $desthost /bin/mkdir $destdir/pg_xlog
ssh -T $desthost /bin/chmod 700 $destdir/pg_xlog

psql -c "SELECT pg_stop_backup()" postgres
