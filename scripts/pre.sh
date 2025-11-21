#!/bin/bash
ulimit -c unlimited

INSTDIR=`pwd`/tmp_install
export LD_LIBRARY_PATH=$INSTDIR/lib:$LD_LIBRARY_PATH
export PATH=$INSTDIR/bin:$PATH

PGPORT1=5432
PGPORT2=5433

pg_ctl -o "-p $PGPORT1" -D $M1 stop
pg_ctl -o "-p $PGPORT2" -D $M2 stop

# Kill all processes
unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
    pkill -U `whoami` -9 -e postgres
	pkill -U `whoami` -9 -e pgbench
	pkill -U `whoami` -9 -e psql
elif [[ "$OSTYPE" == "darwin"* ]]; then
    killall -u `whoami` -vz -9 postgres
    killall -u `whoami` -vz -9 pgbench
    killall -u `whoami` -vz -9 psql
else
    echo "Unintended OS."
fi
sleep 1

M1=`pwd`/pgdata_$PGPORT1
M2=`pwd`/pgdata_$PGPORT2
echo "MMM: $M1 $M2"
U=`whoami`
export PGUSER=$U

rm -rf $M1 || true && mkdir $M1 && rm -rf logfile_$PGPORT1.log || true
rm -rf $M2 || true && mkdir $M2 && rm -rf logfile_$PGPORT2.log || true

export LC_ALL=C
export LC_ALL=en_US.UTF-8
export LANGUAGE="en_US:en"

initdb -D $M1 -U $U --locale=en_US.UTF-8
initdb -D $M2 -U $U --locale=en_US.UTF-8

echo "
  fsync = off
  wal_level = 'logical'
  max_worker_processes = 32
  max_replication_slots = 32
  max_wal_senders = 32
" >> $M1/postgresql.conf

echo "
  fsync = off
  wal_level = 'logical'
  max_worker_processes = 32
  max_replication_slots = 32
  max_wal_senders = 32
" >> $M2/postgresql.conf

#
# Engage !
#
pg_ctl -w -D $M1 -o "-p $PGPORT1" -l logfile_$PGPORT1.log start
pg_ctl -w -D $M2 -o "-p $PGPORT2" -l logfile_$PGPORT2.log start

createdb -p $PGPORT1 $U
createdb -p $PGPORT2 $U
