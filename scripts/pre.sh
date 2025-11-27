#!/bin/bash
ulimit -c unlimited

INSTDIR=`pwd`/tmp_install
export LD_LIBRARY_PATH=$INSTDIR/lib:$LD_LIBRARY_PATH
export PATH=$INSTDIR/bin:$PATH

PGPORT1=5432
PGPORT2=5433
TEST_TIME=600

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

	ipcs -om | awk 'NR>3 && $7==0 {print $2}' | xargs -I {} ipcrm -m {} 2>/dev/null
else
    echo "Unintended OS."
fi

M1=`pwd`/pgdata_$PGPORT1
M2=`pwd`/pgdata_$PGPORT2
echo "MMM: $M1 $M2"
U=`whoami`
export PGUSER=$U

rm -rf $M1 || true && rm -rf logfile_$PGPORT1.log || true && mkdir $M1
rm -rf $M2 || true && rm -rf logfile_$PGPORT2.log || true && mkdir $M2

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

# Create data on the first node and let another node to sync
psql -p $PGPORT1 -f ../../testdb/schema-sales.sql -vwith_data=1
if [[ $? -ne 0 ]]; then
    exit;
fi
psql -p $PGPORT2 -f ../../testdb/schema-sales.sql
if [[ $? -ne 0 ]]; then
    exit;
fi

psql -p $PGPORT1 -c "CREATE PUBLICATION testdb_pub FOR ALL TABLES;"
psql -p $PGPORT2 -c "CREATE PUBLICATION testdb_pub FOR ALL TABLES;"

psql -p $PGPORT2 -c "
  CREATE SUBSCRIPTION sub_$PGPORT1_$PGPORT2
  CONNECTION 'port=$PGPORT1 dbname=$U'
  PUBLICATION testdb_pub
  WITH (copy_data = true, synchronous_commit = off, two_phase = false, origin = 'none', disable_on_error = true)"

psql -p $PGPORT2 -c "SELECT wait_subscriptions(
  report_it := true, timeout := '1 minute', delay := 1)"

psql -p $PGPORT1 -c "
  CREATE SUBSCRIPTION sub_$PGPORT2_$PGPORT1
  CONNECTION 'port=$PGPORT2 dbname=$U'
  PUBLICATION testdb_pub
  WITH (copy_data = false, synchronous_commit = off, two_phase = false, origin = 'none', disable_on_error = true)"

psql -p $PGPORT1 -c "SELECT wait_subscriptions(
  report_it := true, timeout := '1 minute', delay := 1)"

# Check subscriptions before the load:
psql -p $PGPORT1 -c "SELECT subname AS disabled_subscription FROM pg_subscription WHERE subenabled = false;"
psql -p $PGPORT2 -c "SELECT subname AS disabled_subscription FROM pg_subscription WHERE subenabled = false;"


pids=();
pgbench -p 5432 -n -c 5 -j 5 -f ../../testdb/sale.pgb \
	-T $TEST_TIME -P 3 --max-tries=1000 -D region='US' &
pids[0]=$!
pgbench -p 5433 -n -c 5 -j 5 -f ../../testdb/sale.pgb \
	-T $TEST_TIME -P 3 --max-tries=1000 -D region='AUS' &
pids[1]=$!

echo 'replication lag' > lag_node_1.txt
echo 'replication lag' > lag_node_2.txt
psql -p $PGPORT1 -c "
  CALL report_replication_lag(timeout := '$TEST_TIME seconds', report_delay := 3)" 2> lag_node_1.txt &
psql -p $PGPORT2 -c "
  CALL report_replication_lag(timeout := '$TEST_TIME seconds', report_delay := 3)" 2> lag_node_2.txt &

# Check PGDATA size periodically. Good system should converge to some more or
# less stable value. That's no option in our test - we keep history. But WAL
# size should come to a stable value.
echo 'PGDATA-1 | PGDATA-2 | WAL1 | WAL2' > disk_usage.txt
for i in $(seq 1 "$TEST_TIME"); do
    size_node_1=$(du -ms $M1 | awk '{print $1}')
	size_node_2=$(du -ms $M2 | awk '{print $1}')
	size_wal_1=$(du -ms $M1/pg_wal/ | awk '{print $1}')
	size_wal_2=$(du -ms $M2/pg_wal/ | awk '{print $1}')
	echo "$size_node_1 | $size_node_2 | $size_wal_1 | $size_wal_2" >> disk_usage.txt
    sleep 1
done &

for pid in ${pids[*]}; do
  wait $pid;
  result=$?
  if [[ $result -ne 0 ]]; then
    echo "Something wrong has happened, pgbench pid: $pid, code: $result."
    exit 1;
  # 0 - success; 1 - invalid command-line options or internal errors;
  # 2 - database errors or problems in the script
fi
done

# Wait for full synchronisation
psql -p $PGPORT1 -c "
  CALL report_replication_lag(
    timeout := '10 minutes', report_delay := 1, stop_lag := 0)"
psql -p $PGPORT2 -c "
  CALL report_replication_lag(
    timeout := '10 minutes', report_delay := 1, stop_lag := 0)"


psql -p $PGPORT1 -f ../../testdb/analytics.sql
psql -p $PGPORT2 -f ../../testdb/analytics.sql

psql -p $PGPORT1 -c "SELECT usename,sent_lsn,write_lsn FROM pg_stat_replication"
psql -p $PGPORT2 -c "SELECT usename,sent_lsn,write_lsn FROM pg_stat_replication"

psql -p $PGPORT1 -c "SELECT subname FROM pg_subscription WHERE subenabled = false;"
psql -p $PGPORT2 -c "SELECT subname FROM pg_subscription WHERE subenabled = false;"
