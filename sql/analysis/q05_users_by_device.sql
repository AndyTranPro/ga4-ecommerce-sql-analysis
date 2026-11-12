-- =============================================================================
-- Q05 | How are active users distributed across device categories?
-- Source : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- Grain  : one row per device_category, whole period (2020-11-01 to 2021-01-31)
--
-- Definitions (as in the brief):
--   active_users = distinct user_pseudo_id seen on that device category
--
-- Expected check (brief): desktop 158,917 | mobile 109,195 | tablet 6,250
--
-- Note: user_pseudo_id identifies a browser/device, not a person, so a person
-- using a phone and a laptop counts as two users. A few IDs can still appear
-- under more than one category (see QA), so the rows may add up to slightly
-- more than the total distinct users.
-- =============================================================================

WITH by_device AS (
  SELECT
    device.category                AS device_category,
    COUNT(DISTINCT user_pseudo_id) AS active_users
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY device_category
),

total AS (
  SELECT COUNT(DISTINCT user_pseudo_id) AS total_users
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
)

SELECT
  d.device_category,
  d.active_users,
  -- Share of ALL distinct users (not of the row sum), so it stays correct even
  -- if a user appears under more than one device category.
  ROUND(100 * SAFE_DIVIDE(d.active_users, t.total_users), 2) AS pct_of_users
FROM by_device AS d
CROSS JOIN total AS t
ORDER BY d.active_users DESC;


-- =============================================================================
-- Part B (optional) | Which device converts best?
-- The guide's Demographics question asks which device brings the best
-- conversion, which Q05 alone can't answer. Session-level funnel by device:
--   purchase_rate     = sessions with a purchase / sessions
--   buyer_rate        = users who purchased / active users
-- =============================================================================
WITH events AS (
  SELECT
    device.category AS device_category,
    user_pseudo_id,
    event_name,
    CONCAT(
      user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_key,
    ecommerce.purchase_revenue_in_usd AS purchase_revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
by_device AS (
  SELECT
    device_category,
    COUNT(DISTINCT user_pseudo_id)                                     AS active_users,
    COUNT(DISTINCT session_key)                                        AS sessions,
    COUNT(DISTINCT IF(event_name = 'purchase', session_key, NULL))     AS purchase_sessions,
    COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL))  AS purchasers,
    SUM(IF(event_name = 'purchase', purchase_revenue, 0))              AS purchase_revenue
  FROM events
  GROUP BY device_category
)
SELECT
  device_category,
  active_users,
  sessions,
  purchase_sessions,
  purchasers,
  ROUND(purchase_revenue, 2)                                   AS purchase_revenue,
  ROUND(SAFE_DIVIDE(purchase_sessions, sessions), 4)           AS purchase_rate,
  ROUND(SAFE_DIVIDE(purchasers, active_users), 4)              AS buyer_rate,
  ROUND(SAFE_DIVIDE(purchase_revenue, sessions), 2)            AS revenue_per_session
FROM by_device
ORDER BY active_users DESC;


-- =============================================================================
-- QA | How many user IDs appear under more than one device category?
-- Small numbers are normal; a large number would mean the device rows overlap
-- and should not be added together.
-- =============================================================================
-- SELECT COUNT(*) AS users_on_multiple_devices
-- FROM (
--   SELECT user_pseudo_id
--   FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--   WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--   GROUP BY user_pseudo_id
--   HAVING COUNT(DISTINCT device.category) > 1
-- );


-- =============================================================================
-- Dashboard tip (Looker Studio): for a pie or bar of users by device, connect
-- to the raw events (or a user-level table) and use COUNT_DISTINCT(user_pseudo_id)
-- so the counts stay correct when a date filter is applied. Pre-aggregated
-- distinct counts like the ones above can't be re-filtered by date.
-- =============================================================================
