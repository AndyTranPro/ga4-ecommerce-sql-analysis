-- =============================================================================
-- Q01 | Daily overview metrics
-- Source : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- Grain  : one row per event_date (2020-11-01 to 2021-01-31)
--
-- Definitions follow the project brief:
--   session_key            = user_pseudo_id + '-' + ga_session_id
--   sessions               = distinct session keys active that day
--   view_product_rate      = view_item_sessions / sessions
--   view_to_cart_rate      = cart_sessions / view_item_sessions
--   cart_to_purchase_rate  = purchase_sessions / cart_sessions
--   purchase_rate          = purchase_sessions / sessions
--   avg_purchase_revenue   = purchase_revenue / transactions   (AOV)
--   avg_basket_size        = basket_qty / transactions
--   revenue_per_session    = purchase_revenue / sessions       (brief calls this "revenue_per_user")
--   revenue_per_user       = purchase_revenue / active_users   (true per-user figure, added)
--
-- Data-quality notes:
--   1. add_to_cart is barely tracked before mid-Nov 2020 (4 events on 1 Nov vs
--      3,380 view_item). Cart-based rates before ~16 Nov are not meaningful, and
--      cart_to_purchase_rate can exceed 1 because the funnel is presence-based,
--      not ordered.
--   2. A session that crosses midnight is counted on both days (same as GA4 UI).
--      Don't sum daily sessions across days for a period total.
-- =============================================================================

WITH events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    event_name,
    user_pseudo_id,
    CONCAT(
      user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_key,                                   -- NULL if either part is missing
    ecommerce.transaction_id,
    ecommerce.purchase_revenue_in_usd AS purchase_revenue,
    ecommerce.total_item_quantity    AS item_quantity
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),

daily AS (
  SELECT
    event_date,

    -- Session counts (COUNT DISTINCT ignores NULL session keys)
    COUNT(DISTINCT session_key)                                         AS sessions,
    COUNT(DISTINCT IF(event_name = 'view_item',   session_key, NULL))   AS view_item_sessions,
    COUNT(DISTINCT IF(event_name = 'add_to_cart', session_key, NULL))   AS cart_sessions,
    COUNT(DISTINCT IF(event_name = 'purchase',    session_key, NULL))   AS purchase_sessions,

    -- Users
    COUNT(DISTINCT user_pseudo_id)                                      AS active_users,

    -- Ecommerce (ecommerce.* is only populated on purchase events)
    COUNTIF(event_name = 'purchase')                                    AS ecommerce_purchases,
    COUNT(DISTINCT IF(
      event_name = 'purchase'
        AND LOWER(transaction_id) NOT IN ('(not set)', '(data deleted)', '<other>'),
      transaction_id, NULL))                                            AS transactions,
    SUM(IF(event_name = 'purchase', purchase_revenue, 0))               AS purchase_revenue,
    SUM(IF(event_name = 'purchase', item_quantity, 0))                  AS basket_qty
  FROM events
  GROUP BY event_date
)

SELECT
  event_date,
  sessions,
  ROUND(SAFE_DIVIDE(view_item_sessions, sessions), 4)            AS view_product_rate,
  ROUND(SAFE_DIVIDE(cart_sessions, view_item_sessions), 4)       AS view_to_cart_rate,
  ROUND(SAFE_DIVIDE(purchase_sessions, cart_sessions), 4)        AS cart_to_purchase_rate,
  ROUND(SAFE_DIVIDE(purchase_sessions, sessions), 4)             AS purchase_rate,
  ecommerce_purchases,
  transactions,
  ROUND(purchase_revenue, 2)                                     AS purchase_revenue,
  ROUND(SAFE_DIVIDE(purchase_revenue, transactions), 2)          AS avg_purchase_revenue,
  ROUND(SAFE_DIVIDE(basket_qty, transactions), 2)                AS avg_basket_size,
  ROUND(SAFE_DIVIDE(purchase_revenue, sessions), 2)              AS revenue_per_session,
  ROUND(SAFE_DIVIDE(purchase_revenue, active_users), 2)          AS revenue_per_user,

  -- Raw counts kept so results can be checked and re-aggregated
  view_item_sessions,
  cart_sessions,
  purchase_sessions,
  active_users,
  basket_qty
FROM daily
ORDER BY event_date;


-- =============================================================================
-- QA | Run once. If many transaction IDs repeat, purchase_revenue double-counts
-- those orders, so de-duplicate by transaction_id before summing revenue.
-- =============================================================================
-- SELECT
--   COUNT(*)                                     AS purchase_events,
--   COUNT(DISTINCT ecommerce.transaction_id)     AS distinct_transaction_ids,
--   COUNTIF(ecommerce.transaction_id = '(not set)') AS not_set_ids
-- FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
-- WHERE event_name = 'purchase';


-- =============================================================================
-- Dashboard tip (Looker Studio): save the `daily` CTE as a table and build the
-- rates as calculated fields, e.g. SUM(purchase_sessions) / SUM(sessions),
-- so they stay correct when the viewer changes the date range.
-- =============================================================================
