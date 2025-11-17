/*
 * Analytics.
 *
 * Here, are some queries to check data consistency.
 */

-- Just to see how much work was done and where.
SELECT * FROM periods;

SELECT count(*) FROM sales WHERE success = true;

SELECT count(*) FROM sales WHERE success = false
  UNION ALL
SELECT sum(counter) FROM exceptions;
