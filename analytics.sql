/*
 * Analytics.
 *
 * Here, are some queries to check data consistency.
 */

-- Just to see how much work was done and where.
SELECT * FROM periods ORDER BY value;

SELECT count(*) FROM sales WHERE success = true;

SELECT count(*) FROM sales WHERE success = false
  UNION ALL
SELECT sum(counter) FROM exceptions;

-- Sales on each period for specific depot
SELECT p.id,depot_id, count(*) FROM sales s
  JOIN periods p ON (s.period = p.value)
WHERE success = true AND p.country = 'US'
GROUP BY id,depot_id ORDER BY id,depot_id;

-- Sum supplies on each period for specific depot

SELECT sum(counter) FROM exceptions;
SELECT * FROM deliveries;


SELECT p.id,depot_id, sum(delta) FROM deliveries d
  JOIN periods p ON (d.period = p.value)
WHERE p.country = 'US'
GROUP BY id,depot_id ORDER BY id,depot_id;