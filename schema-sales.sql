DROP TABLE IF EXISTS
  supplies,sales,exceptions,depots,products,periods,deliveries
CASCADE;
DROP FUNCTION IF EXISTS do_sale,is_supplier,supply_calc;
DROP PROCEDURE IF EXISTS do_supply,add_depots,schema_init;

-- Number of depots at each region
\set depots_num 5

\set products_num 1000

/* *****************************************************************************
 *
 * TABLE Definitions
 *
 **************************************************************************** */
CREATE TABLE depots (
	depot_id serial,
	label    name NOT NULL,
	country  name NOT NULL,
	active   boolean DEFAULT true,
	PRIMARY KEY (depot_id)
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
  sale_id    serial,
  country    name,
  depot_id   integer REFERENCES depots (depot_id),
  product_id integer REFERENCES products (product_id),
  period     bigint,
  success    boolean,
  PRIMARY KEY (sale_id,country) -- two elements to avoid conflicts
);
CREATE TABLE exceptions (
  depot_id   integer REFERENCES depots (depot_id),
  product_id integer REFERENCES products (product_id),
  period     bigint,
  counter    integer,
  PRIMARY KEY (depot_id, product_id, period)
);
CREATE TABLE periods (
	country     name NOT NULL, -- Need to separate instance's data access
	value       bigint,
	create_time TimestampTz DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (value, country)
);
CREATE TABLE deliveries (
  depot_id   integer REFERENCES depots (depot_id),
  product_id integer REFERENCES products (product_id),
  period     bigint,
  delta      integer,
  PRIMARY KEY (depot_id,product_id,period)
);

/* *****************************************************************************
 *
 * Service routines
 *
 **************************************************************************** */

--
-- Am I a supplier in the region?
--
CREATE FUNCTION is_supplier(period bigint, region name)
RETURNS boolean AS $$
DECLARE
	c_period bigint;
BEGIN
  SELECT COALESCE(max(value),0) FROM periods INTO c_period
  WHERE country = region;
  IF (period > c_period) THEN
	INSERT INTO periods (value,country) VALUES (period, region);
	
	-- In the REPEATABLE READ case only one client will arrive here - others
	-- will be aborted and re-trying will be in the new period.
	raise LOG '--> Create new period % in region %', period,region;
	RETURN true;
  END IF;
  
  -- Normal case: no supply needed, just go shopping.
  RETURN false;
  
  EXCEPTION
    WHEN OTHERS THEN
	 NULL;
  
  RETURN false;
END;
$$ LANGUAGE plpgsql;

/*
 * Perform supply
 *
 * Pass through each (depot,product) record, calculate necessary quantity and
 * perform update
 */
CREATE PROCEDURE do_supply(region name, period bigint)
AS $$
DECLARE
	r record;
BEGIN
  raise LOG '--> supply % %', region, period;
  CREATE TEMPORARY TABLE tdata AS
    SELECT s.depot_id,s.product_id,s.quantity,s.quantity_predicted AS plan,
	  supply_calc(quantity_predicted, quantity) AS delta
	FROM supplies s JOIN depots d USING (depot_id) WHERE d.country = region;
  
  FOR r IN SELECT * FROM tdata LOOP
	-- Calculate necessary supply and UPDATE the row
	UPDATE supplies
	SET quantity = quantity + r.delta, quantity_predicted = r.quantity + r.delta
	WHERE depot_id = r.depot_id AND product_id = r.product_id;
	
	INSERT INTO deliveries (depot_id,product_id,period,delta)
	  VALUES (r.depot_id, r.product_id, period, r.delta);
	COMMIT;
  END LOOP;
  
  DROP TABLE tdata;
END;
$$ LANGUAGE plpgsql;

/*
 * Perform sale logic:
 * 1. Check availability of the product.
 * 2. Sale it or complain into exceptions.
 * 3. Write the fact of the sale attempt.
 *
 * TODO: In case of unsuccessful sale check the counter. If it is too big, try
 * to request products from another depot.
 */
CREATE FUNCTION do_sale(region name, d_id integer,pr_id integer, per_id bigint)
RETURNS VOID AS $$
DECLARE
	qty integer;
BEGIN
  -- raise LOG '--> do sale % % %', d_id, pr_id, per_id;
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
  INSERT INTO sales (country, depot_id,product_id,period,success)
    VALUES (region, d_id, pr_id, per_id, (qty > 0)::boolean);
END;
$$ LANGUAGE plpgsql;

--
-- Calculate how much quantity of each product we should deliver to the depot
--
CREATE FUNCTION supply_calc(qp integer, balance integer)
RETURNS integer AS $$
DECLARE
	delta integer;
	p     integer;
BEGIN
  delta := qp - balance;
  
  IF (delta < 0) THEN
    raise EXCEPTION 'Incorrect balance in the depot: (%, %)', qp, balance;
  END IF;
  
  -- Add variable part into the 10%. It makes our data more lively ;)
  p :=  delta * ((0.2 * random()) - (0.2 * random()));
  
  IF (balance + delta + p <= 0) THEN
    -- safety measure
    RETURN 0;
  END IF;

  RETURN delta + p;
END;
$$ LANGUAGE plpgsql STRICT VOLATILE;

/*
 * Calling it on a working system there are conflicts may happen.
 * Use REPEATABLE READ Tx PREPARED and retry the call if needed.
 */
CREATE PROCEDURE add_depots(region name, depots_num integer) AS $$
DECLARE
	max_num bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM periods
				 WHERE country = region AND value = 0) THEN
    -- New region detected.
    INSERT INTO periods (country, value) VALUES (region, 0);
  END IF;
  
  max_num := COALESCE((SELECT MAX(depot_id) FROM depots), 0);
  raise NOTICE 'max_num % %', max_num, depots_num;
  INSERT INTO depots (label, country)
    SELECT 'Depot ID - ' || value, region
  FROM generate_series(max_num + 1,max_num + depots_num) AS value;
END;
$$ LANGUAGE plpgsql;

/*
 * Any additional environment-dependent instructions should be placed here
 */
CREATE PROCEDURE schema_init(nodenum integer) AS $$
BEGIN
  IF (nodenum > 0) THEN
    -- CREATE EXTENSION IF NOT EXISTS snowflake;
  END IF;
END;
$$ LANGUAGE plpgsql;

/* *****************************************************************************
 *
 * Initialization code
 *
 **************************************************************************** */
 
-- In case we have multiple active instances
-- Will be skipped if node number is set
\if :{?with_data}
  \echo "Generate data"

  CALL add_depots('US', :depots_num);
  CALL add_depots('AUS', :depots_num);

  INSERT INTO products (product_id, label)
  SELECT value, 'Product No. ' || value
  FROM generate_series(1,:products_num) AS value;

  -- Initially, each depot contains zero value of each product: first incoming
  -- transaction will perform supply.
  INSERT INTO supplies (depot_id, product_id, quantity, quantity_predicted)
    SELECT depot_id,product_id,0,100 FROM depots, products;

\else
  \set with_data 0
  \echo "Schema only mode"
\endif

CALL schema_init(:with_data);

ANALYZE;

/*
 * Wait until each subscription will finish initial syncing.
 *
 * Convenience funtion.
 */
CREATE FUNCTION wait_subscriptions(
  report_it boolean DEFAULT false,
  timeout   interval DEFAULT '0 second',
  delay     real DEFAULT 1.
)
RETURNS boolean AS $$
DECLARE
  end_time           Timestamp := 'infinity';
  time_remained      Interval;
  result             boolean := false;
  state              record;
  srsubstate         text;
BEGIN
  -- Calculate the End Time, if requested.
  IF timeout > '0 second' THEN
    SELECT now() + timeout INTO end_time;
  END IF;

  -- Subscription must exist and enabled
  ASSERT NOT EXISTS (SELECT subname FROM pg_subscription WHERE subenabled = false);
  ASSERT EXISTS (SELECT subname FROM pg_subscription WHERE subenabled = true);

  srsubstate := sr.srsubstate FROM pg_subscription_rel sr
						 			WHERE sr.srsubstate NOT IN ('s') LIMIT 1;
  WHILE (srsubstate NOT IN ('s', 'r'))
  LOOP
    SELECT sr.srsubstate,s.subname, c.relname
	FROM pg_subscription_rel sr, pg_subscription s, pg_class c
	WHERE sr.srsubstate NOT IN ('s') AND sr.srrelid = c.oid AND s.oid = sr.srsubid
	LIMIT 1 INTO state;
	srsubstate := state.srsubstate;
										
    SELECT end_time - clock_timestamp() INTO time_remained;
    IF time_remained < '0 second' THEN
      RETURN false;
    END IF;
	IF report_it = true THEN
      raise NOTICE 'Syncing subscription % detected (relation: %), Time remained: % (HH24:MI:SS)',
	    state.subname, state.relname,
        to_char(time_remained, 'HH24:MI:SS');
    END IF;
    PERFORM pg_sleep(delay);
  END LOOP;
  
  RETURN true;
END;
$$ LANGUAGE plpgsql STRICT VOLATILE;
