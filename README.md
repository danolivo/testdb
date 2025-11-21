# testdb
Database for testing purposes 

# Usage
Initialise the schema:
```
psql -f schema-sales.sql
```

Use `-D varname=value` to identify specific region that was covered by a specific
subset of pgbench clients.

## The example:

_'sales in two regions, each one covered by separate set of pgbench clients'_

One instance case.

```
psql -f ../testdb/schema-sales.sql
pgbench -n -c 5 -j 5 -f ../testdb/sale.pgb -T 30 -P 3 --max-tries=1000 -D region='US' &
pgbench -n -c 5 -j 5 -f ../testdb/sale.pgb -T 30 -P 3 --max-tries=1000 -D region='AUS' &
psql -f ../testdb/analytics.sql
```
