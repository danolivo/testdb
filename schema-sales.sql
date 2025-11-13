DROP TABLE IF EXISTS
  supplies,sales,exceptions,depots,products,periods
CASCADE;

\set depots_num 10
\set products_num 1000

CREATE TABLE depots (
	depot_id integer PRIMARY KEY,
	label    name NOT NULL,
	active   boolean DEFAULT true
);
CREATE TABLE products (
	product_id integer PRIMARY KEY,
	label      name NOT NULL,
	active     boolean DEFAULT true
);
CREATE TABLE supplies (
  depot_id           integer REFERENCES depots (depot_id),
  product_id         integer REFERENCES products (product_id),
  quantity           integer NOT NULL CHECK (quantity >= 0),
  quantity_predicted integer NOT NULL CHECK (quantity_predicted >= 0),
  PRIMARY KEY (depot_id, product_id)
);
CREATE TABLE sales (
  sale_id    serial PRIMARY KEY,
  depot_id   integer REFERENCES depots (depot_id),
  product_id integer REFERENCES products (product_id),
  period     integer,
  success    boolean
);
CREATE TABLE exceptions (
  depot_id   integer REFERENCES depots (depot_id),
  product_id integer REFERENCES products (product_id),
  period     integer,
  counter    integer,
  PRIMARY KEY (depot_id, product_id, period)
);
CREATE TABLE periods (
	id    serial,
	value bigint PRIMARY KEY
);

INSERT INTO depots (depot_id,label)
  SELECT value, 'Depot No. ' || value
  FROM generate_series(1,:depots_num) AS value;
INSERT INTO products (product_id,label)
  SELECT value, 'Product No. ' || value
  FROM generate_series(1,:products_num) AS value;

-- Initially, each depot contains zero value of each product: first incoming
-- transaction will perform supply.
INSERT INTO supplies (depot_id,product_id,quantity,quantity_predicted)
  SELECT depot_id,product_id,0,1000 FROM depots, products;

ANALYZE;
