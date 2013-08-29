#! /bin/sh
# Recovery script for streaming replication.
# This script assumes that DB node 0 is primary, and 1 is standby.
#
datadir=$1
desthost=$2
destdir=$3

psql -c "SELECT pg_start_backup('Streaming Replication', true)" postgres

rsync -C -a --delete -e ssh --exclude postmaster.pid \
--exclude postmaster.opts --exclude pg_log --exclude pg_xlog \
--exclude recovery.conf --exclude recovery.done $datadir/ $desthost:$destdir/

ssh -T localhost mv $destdir/recovery.done $destdir/recovery.conf

psql -c "SELECT pg_stop_backup()" postgres
