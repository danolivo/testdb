# testdb
Database for testing purposes

# Usage
Initialise the schema:
```
psql -f schema-sales.sql
```

Use `-D varname=value` to identify specific region that was covered by a specific
subset of pgbench clients.

## Example No.1

_'sales in two regions, each one covered by separate set of pgbench clients'_

One instance case.

```
psql -f ../../testdb/schema-sales.sql -vwith_data=1
pgbench -n -c 5 -j 5 -f ../../testdb/sale.pgb -T 360 -P 3 --max-tries=1000 -D region='US' &
pgbench -n -c 5 -j 5 -f ../../testdb/sale.pgb -T 360 -P 3 --max-tries=1000 -D region='AUS'
psql -f ../../testdb/analytics.sql
```

At some point in time you may decide to open the company's branch in one more country.
Add depots, fill them with products and start load by something like the following:

```
psql -c "CALL add_depots('KAZ', 3);"
psql -c "INSERT INTO supplies (depot_id, product_id, quantity, planned)
           SELECT depot_id,product_id,0,100 FROM depots d, products
		   WHERE d.country = 'KAZ' AND active = true"
pgbench -n -c 2 -j 2 -f ../../testdb/sale.pgb -T 360 -P 3 --max-tries=1000 -D region='KAZ'
```

## Example No.2

_Two instances with a cross replication_

```

Use scripts/pre.sh to init and launch demo of the two-node configuration

```

# Replication lag

SELECT usename,sent_lsn,write_lsn FROM pg_stat_replication;
SELECT subname FROM pg_subscription WHERE subenabled = false;
