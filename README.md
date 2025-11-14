# testdb
Database for testing purposes 

# Usage
Initialise the schema:
```
psql -f schema-sales.sql
```

Simple launch:
```
pgbench -n -t 1 -f sale.pgb

psql -f ../../testdb/schema-sales.sql
pgbench -n -c 5 -j 5 -f ../../testdb/sale.pgb -T 30 -P 3 --max-tries=0
```
