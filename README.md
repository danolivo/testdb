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
```
