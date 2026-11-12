-- =============================================================================
-- Q04 | For each traffic source/medium: how many session starts, product views,
--       checkouts, purchases and first-time purchasers?
-- Source : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- Grain  : one row per source x medium, whole period (2020-11-01 to 2021-01-31)
--
-- Brief columns and how they are calculated:
--   started_users         = distinct users with a session_start event
--                           (the brief labels this column "sessions", but its
--                           hint and expected numbers count USERS, not sessions)
--   item_view_events      = count of view_item events
--   checkouts             = count of begin_checkout events
--   ecommerce_purchases   = count of purchase events
--   first_time_purchasers = users with a first_visit event in the period who
--                           also purchased in the period
--
-- Added columns (clearly not in the brief):
--   sessions              = distinct session keys on session_start (matches Q03)
--   transactions          = distinct valid transaction IDs
--   purchases_per_100_sessions, checkout_to_purchase_rate
--
-- Expected check (brief): google / organic -> started_users 102,530,
--   item_view_events 116,917, checkouts 10,642, ecommerce_purchases 1,454,
--   first_time_purchasers 1,255.
--
-- Why the first-time definition works: the data starts on 2020-11-01. A user
-- whose first_visit is inside the period cannot have bought before it, so any
-- purchase they make is their first ever. Buyers WITHOUT a first_visit here may
-- also be first-time buyers, but the data can't prove it, so they are excluded.
--
-- Reminder: traffic_source.* is the source that FIRST acquired the user (see Q03).
-- =============================================================================

WITH events AS (
  SELECT
    traffic_source.source AS session_source,
    traffic_source.medium AS session_medium,
    user_pseudo_id,
    event_name,
    CONCAT(
      user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_key,
    ecommerce.transaction_id,
    -- TRUE on every row of a user who purchased at least once in the period.
    -- A window function avoids a second scan or a correlated EXISTS subquery.
    LOGICAL_OR(event_name = 'purchase') OVER (PARTITION BY user_pseudo_id) AS user_has_purchase
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),

by_source AS (
  SELECT
    session_source,
    session_medium,

    -- Brief columns
    COUNT(DISTINCT IF(event_name = 'session_start', user_pseudo_id, NULL))   AS started_users,
    COUNTIF(event_name = 'view_item')                                        AS item_view_events,
    COUNTIF(event_name = 'begin_checkout')                                   AS checkouts,
    COUNTIF(event_name = 'purchase')                                         AS ecommerce_purchases,
    COUNT(DISTINCT IF(event_name = 'first_visit' AND user_has_purchase,
                      user_pseudo_id, NULL))                                 AS first_time_purchasers,
    -- To replicate the brief's Note exactly (it counts first_visit EVENTS),
    -- swap the line above for:
    -- COUNTIF(event_name = 'first_visit' AND user_has_purchase) AS first_time_purchasers,

    -- Added columns
    COUNT(DISTINCT IF(event_name = 'session_start', session_key, NULL))      AS sessions,
    COUNT(DISTINCT IF(event_name = 'purchase'
                        AND LOWER(transaction_id) NOT IN ('(not set)', '(data deleted)', '<other>'),
                      transaction_id, NULL))                                 AS transactions
  FROM events
  GROUP BY session_source, session_medium
)

SELECT
  session_source,
  session_medium,
  started_users,
  item_view_events,
  checkouts,
  ecommerce_purchases,
  first_time_purchasers,
  -- extras
  sessions,
  transactions,
  ROUND(100 * SAFE_DIVIDE(ecommerce_purchases, sessions), 2) AS purchases_per_100_sessions,
  ROUND(SAFE_DIVIDE(ecommerce_purchases, checkouts), 4)      AS checkout_to_purchase_rate
FROM by_source
ORDER BY started_users DESC;


-- =============================================================================
-- How to read it ("which channel is most effective?")
--   * Volume: started_users / sessions show reach.
--   * Efficiency: purchases_per_100_sessions and checkout_to_purchase_rate show
--     how well each channel converts; compare these, not raw purchase counts.
--   * New-customer acquisition: first_time_purchasers shows which channels bring
--     in buyers who are new to the store.
--   * Ignore tiny rows (e.g. <Other> / cpc with 1 session) when ranking rates,
--     and treat '<Other>' / '(data deleted)' as obfuscated, not real channels.
-- =============================================================================


-- =============================================================================
-- QA 1 | Does any user carry more than one source/medium label?
-- If this returns a large number, the same user is split across rows and
-- user counts per row will add up to more than the total number of users.
-- =============================================================================
-- SELECT COUNT(*) AS users_with_multiple_labels
-- FROM (
--   SELECT user_pseudo_id
--   FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--   WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--   GROUP BY user_pseudo_id
--   HAVING COUNT(DISTINCT CONCAT(IFNULL(traffic_source.source, ''), '|',
--                                IFNULL(traffic_source.medium, ''))) > 1
-- );


-- =============================================================================
-- QA 2 | Event-count columns must add up to the overall totals.
-- Compare with SUM(item_view_events), SUM(checkouts), SUM(ecommerce_purchases)
-- from the main query; they should be identical.
-- =============================================================================
-- SELECT
--   COUNTIF(event_name = 'view_item')      AS item_view_events,
--   COUNTIF(event_name = 'begin_checkout') AS checkouts,
--   COUNTIF(event_name = 'purchase')       AS ecommerce_purchases
-- FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
-- WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131';
