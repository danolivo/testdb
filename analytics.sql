/*
 * Analytics.
 *
 * Here, are some queries to check data consistency.
 */

-- Just to see how much work was done and where.
SELECT country,value,to_char(create_time, 'HH24:MI:SS') AS created_at
FROM periods ORDER BY create_time,value;

-- Integral checks:

-- Check: sum of all deliveries - leftovers == sales
SELECT count(*) AS sold FROM sales WHERE success = true
UNION ALL (
SELECT delivered - leftovers FROM
  (SELECT sum(delta) AS delivered FROM deliveries),
  (SELECT sum(quantity) AS leftovers FROM supplies)
);

-- Check: unsuccessful sales
SELECT 'exceptions' AS title, sum(counter) AS number FROM exceptions
	UNION ALL
SELECT 'unsuccessful sales', count(*) FROM sales WHERE success = false;

-- Checks for each depot:

-- Failed sales:
SELECT * FROM (
  SELECT sum(counter) AS exceptions, depot_id
  FROM exceptions GROUP BY depot_id
) JOIN (
  SELECT count(*) AS "failed sales", depot_id
  FROM sales WHERE success = false GROUP BY depot_id)
  USING (depot_id)
ORDER BY depot_id;

-- Successful sales:
SELECT * FROM (
  SELECT depot_id, delivered - leftovers AS sold_1 FROM
    (SELECT depot_id, sum(delta) AS delivered FROM deliveries GROUP BY depot_id)
      JOIN
    (SELECT depot_id, sum(quantity) AS leftovers FROM supplies GROUP BY depot_id)
    USING (depot_id)
  ) JOIN (
	  SELECT depot_id, count(*) AS sold_2 FROM sales
	  WHERE success = true GROUP BY depot_id
  ) USING (depot_id)
ORDER BY depot_id;

/*
 * Just analytics
 */

-- Sale dynamics throughout the periods
SELECT count(*) FROM sales GROUP BY period ORDER BY period;

-- Total delivery dynamics
SELECT period,sum(delta) FROM deliveries
GROUP BY period
ORDER BY period;