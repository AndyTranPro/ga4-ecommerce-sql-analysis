-- =============================================================================
-- Q06 | Which countries have the highest number of active users?
-- Source : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- Grain  : one row per country, whole period (2020-11-01 to 2021-01-31)
--
-- Definitions (as in the brief):
--   active_users = distinct user_pseudo_id seen in that country
--
-- Expected check (brief): United States 118,493 | India 25,367 |
--   Canada 20,268 | United Kingdom 8,527 | France 5,381
--
-- Notes:
--   * Country comes from the IP address of each event, so a user who travels
--     or uses a VPN can appear under more than one country (see QA 1).
--   * '(not set)' means GA4 could not resolve the location. It is kept as its
--     own row so the total stays complete; filter it out for charts if needed.
-- =============================================================================

WITH by_country AS (
  SELECT
    geo.country                    AS country,
    COUNT(DISTINCT user_pseudo_id) AS active_users
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY country
),

total AS (
  SELECT COUNT(DISTINCT user_pseudo_id) AS total_users
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
)

SELECT
  RANK() OVER (ORDER BY c.active_users DESC)                     AS country_rank,
  c.country,
  c.active_users,
  ROUND(100 * SAFE_DIVIDE(c.active_users, t.total_users), 2)     AS pct_of_users,
  -- Running share shows how concentrated the audience is
  -- (e.g. "the top 5 countries hold X% of users").
  ROUND(100 * SAFE_DIVIDE(
    SUM(c.active_users) OVER (ORDER BY c.active_users DESC, c.country
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
    t.total_users), 2)                                           AS cumulative_pct
FROM by_country AS c
CROSS JOIN total AS t
ORDER BY c.active_users DESC, c.country;
-- cumulative_pct is approximate: users seen in several countries are counted
-- once per country, so it can slightly exceed 100 at the tail.


-- =============================================================================
-- Part B (optional) | Which countries convert best?
-- Answers the guide's Demographics question. Countries with fewer than 1,000
-- sessions are excluded so tiny samples don't top the ranking by chance
-- (one purchase from 10 sessions looks like a 10% purchase rate).
-- =============================================================================
WITH events AS (
  SELECT
    geo.country AS country,
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
by_country AS (
  SELECT
    country,
    COUNT(DISTINCT user_pseudo_id)                                     AS active_users,
    COUNT(DISTINCT session_key)                                        AS sessions,
    COUNT(DISTINCT IF(event_name = 'purchase', session_key, NULL))     AS purchase_sessions,
    COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL))  AS purchasers,
    SUM(IF(event_name = 'purchase', purchase_revenue, 0))              AS purchase_revenue
  FROM events
  GROUP BY country
)
SELECT
  country,
  active_users,
  sessions,
  purchase_sessions,
  purchasers,
  ROUND(purchase_revenue, 2)                               AS purchase_revenue,
  ROUND(SAFE_DIVIDE(purchase_sessions, sessions), 4)       AS purchase_rate,
  ROUND(SAFE_DIVIDE(purchasers, active_users), 4)          AS buyer_rate,
  ROUND(SAFE_DIVIDE(purchase_revenue, sessions), 2)        AS revenue_per_session
FROM by_country
WHERE sessions >= 1000          -- minimum volume; adjust and state it in your write-up
ORDER BY purchase_rate DESC;


-- =============================================================================
-- QA 1 | How many user IDs appear in more than one country?
-- =============================================================================
-- SELECT COUNT(*) AS users_in_multiple_countries
-- FROM (
--   SELECT user_pseudo_id
--   FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--   WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--   GROUP BY user_pseudo_id
--   HAVING COUNT(DISTINCT geo.country) > 1
-- );


-- =============================================================================
-- QA 2 | Placeholder and blank country values: how big are they?
-- =============================================================================
-- SELECT geo.country, COUNT(DISTINCT user_pseudo_id) AS active_users
-- FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
-- WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--   AND (geo.country IS NULL OR TRIM(geo.country) = ''
--        OR geo.country IN ('(not set)', '(data deleted)', '<Other>'))
-- GROUP BY geo.country;


-- =============================================================================
-- Dashboard tip (Looker Studio): use a Geo chart with Country as the dimension
-- and COUNT_DISTINCT(user_pseudo_id) on raw or user-level data, so the map
-- respects date filters. Show a "Top 10 countries" table beside it, because
-- the US dominates and smaller countries are hard to read on a map.
-- =============================================================================
