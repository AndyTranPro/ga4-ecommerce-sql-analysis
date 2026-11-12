-- =============================================================================
-- Q02 | What user actions (event_name) does the website track?
-- Source : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- Grain  : one row per event_date x event_name (2020-11-01 to 2021-01-31)
--
-- Metrics (as defined in the brief):
--   event_count    = number of events with that name on that day
--   event_percent  = event_count / total events that day
--   active_users   = distinct user_pseudo_id who fired that event that day
--
-- Expected check (brief): 2020-11-01, page_view -> event_count 9,767,
--   event_percent ~0.3123 (31.2% of 31,272 events), active_users 2,302.
--
-- Notes:
--   * event_percent sums to 1 within each day.
--   * active_users is distinct per day AND per event, so it cannot be summed
--     across events or days (one user fires many event types).
-- =============================================================================

WITH daily_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date)  AS event_date,
    event_name,
    COUNT(*)                          AS event_count,
    COUNT(DISTINCT user_pseudo_id)    AS active_users
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY event_date, event_name
)

SELECT
  event_date,
  event_name,
  event_count,
  SAFE_DIVIDE(event_count, SUM(event_count) OVER (PARTITION BY event_date)) AS event_percent,
  active_users
FROM daily_events
ORDER BY event_date, event_count DESC;


-- =============================================================================
-- Part B | "List them all": every event type tracked over the whole period
-- One row per event_name. Answers the question directly without the daily split.
-- =============================================================================
SELECT
  event_name,
  COUNT(*)                                             AS event_count,
  ROUND(SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 4) AS event_percent,
  COUNT(DISTINCT user_pseudo_id)                       AS active_users,
  COUNT(DISTINCT event_date)                           AS days_tracked,   -- out of 92
  MIN(PARSE_DATE('%Y%m%d', event_date))                AS first_seen,
  MAX(PARSE_DATE('%Y%m%d', event_date))                AS last_seen
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
GROUP BY event_name
ORDER BY event_count DESC;
-- Tip: days_tracked and first_seen expose tracking gaps, e.g. add_to_cart is
-- near zero in early Nov 2020, which affects cart-based rates in Q01 and Q09.


-- =============================================================================
-- QA | Every day should be present and its shares should add up to 1.
-- Expected output: zero rows, and the date check returns 92 days.
-- =============================================================================
-- WITH q02 AS (
--   SELECT
--     PARSE_DATE('%Y%m%d', event_date) AS event_date,
--     event_name,
--     SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER (PARTITION BY event_date)) AS event_percent
--   FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--   WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--   GROUP BY event_date, event_name
-- )
-- SELECT event_date, SUM(event_percent) AS total_share
-- FROM q02
-- GROUP BY event_date
-- HAVING ABS(SUM(event_percent) - 1) > 1e-9;
--
-- Date coverage check (expect 92):
-- SELECT COUNT(DISTINCT event_date) AS days
-- FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
-- WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131';


-- =============================================================================
-- Dashboard tip (Looker Studio): use event_date, event_name and event_count as
-- the source, and build event_percent as a calculated field:
--   SUM(event_count) / SUM(event_count) at the date level (or "Percent of total"
--   in the chart's comparison settings), so it stays right under any filter.
-- =============================================================================
