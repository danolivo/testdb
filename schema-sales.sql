DROP TABLE IF EXISTS
  supplies,sales,exceptions,depots,products,periods
CASCADE;
DROP FUNCTION IF EXISTS do_sale,is_supplier;

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
  SELECT depot_id,product_id,0,100 FROM depots, products;

ANALYZE;

CREATE FUNCTION is_supplier(period integer)
RETURNS boolean AS $$
DECLARE
	c_period integer;
BEGIN
  SELECT COALESCE(max(value),0) FROM periods INTO c_period;
  IF (period > c_period) THEN
	INSERT INTO periods (value) VALUES (period);
	
	-- In the REPEATABLE READ case only one client will arrive here - others
	-- will be aborted and re-trying will be in the new period.
	RETURN true;
  END IF;
  
  -- Normal case: no supply needed, just go shopping.
  RETURN false;
END;
$$ LANGUAGE plpgsql;

/*
 * Perform sale logic:
 * 1. Check availability of the product.
 * 2. Sale it or complain into exceptions.
 * 3. Write the fact of the sale attempt.
 *
 * TODO: In case of unsuccessful sale checl the counter. If it is too big, try
 * to request products from another depot.
 */
CREATE FUNCTION do_sale(d_id integer,pr_id integer, per_id bigint)
RETURNS VOID AS $$
DECLARE
	qty integer;
BEGIN
  SELECT quantity AS qty FROM supplies
    WHERE depot_id = d_id AND product_id = pr_id INTO qty;

  IF (qty > 0) THEN
    -- Main track
    UPDATE supplies SET quantity = quantity - 1
    WHERE depot_id = d_id AND product_id = pr_id;
  ELSE
    -- We apologise to the client and mark we need more
	INSERT INTO exceptions AS e (depot_id,product_id,period,counter)
      VALUES (d_id, pr_id, per_id, 1)
      ON CONFLICT (depot_id,product_id,period)
      DO UPDATE SET counter = e.counter + 1;
  END IF;

  -- log the sale
  INSERT INTO sales (depot_id,product_id,period,success)
    VALUES (d_id, pr_id, per_id, (qty > 0)::boolean);
END;
$$ LANGUAGE plpgsql;

