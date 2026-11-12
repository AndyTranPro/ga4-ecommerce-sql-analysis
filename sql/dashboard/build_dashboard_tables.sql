-- =============================================================================
-- GA4 eCommerce | Dashboard tables for Looker Studio
-- Source : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- Period : 2020-11-01 to 2021-01-31
--
-- HOW TO RUN
--   1. Open BigQuery, select your own project in the top bar.
--   2. Paste this whole file and click Run. It runs as one script, top to
--      bottom, and creates the dataset `ga4_portfolio` plus 7 tables.
--   3. Run the QA block at the end. Every check should return 0 or TRUE.
--
-- TABLES (each one feeds several charts; ratios are NOT stored, they are
-- built as Looker Studio calculated fields so they stay right under filters)
--   stg_events             one row per raw event, nested fields flattened
--   fact_session           one row per session         -> Q01, Q03, Q04, Q10, bounce
--   fact_order             one row per purchase event  -> revenue, AOV, basket
--   fact_event_user_daily  one row per day x event x user x dims -> Q02, Q04-Q07
--   fact_page              one row per page_view       -> Q08
--   fact_item              one row per product in an event -> Q09
--   dim_user               one row per user            -> new users, first-time buyers
--
-- SANDBOX NOTE
--   BigQuery Sandbox (no billing) deletes tables after 60 days, and applies a
--   60-day PARTITION expiry based on the partition DATE. Partitions dated 2020
--   would therefore be deleted at once, so these tables are CLUSTERED, not
--   partitioned. With billing enabled you can add
--   `PARTITION BY <date column>` before CLUSTER BY on each table.
--   If a table disappears after 60 days, just run this script again.
--
-- Cost: one full scan of the public table (a few GB), well inside the free
-- 1 TB/month of query processing.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS ga4_portfolio
OPTIONS (location = 'US');          -- must match the public dataset's location


-- -----------------------------------------------------------------------------
-- 1. stg_events | one row per raw event
-- Unnests the parameters we need once, so every later table reads a flat,
--     small table instead of re-scanning the nested public data.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE ga4_portfolio.stg_events
CLUSTER BY event_name, event_date
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date)                                       AS event_date,
  event_timestamp,                                                       -- microseconds since epoch
  event_name,
  user_pseudo_id,
  (SELECT MAX(value.int_value) FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  CONCAT(
    user_pseudo_id, '-',
    CAST((SELECT MAX(value.int_value) FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  )                                                                      AS session_key,
  (SELECT MAX(value.string_value) FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT MAX(value.string_value) FROM UNNEST(event_params) WHERE key = 'page_title')    AS page_title,
  (SELECT MAX(COALESCE(value.string_value, CAST(value.int_value AS STRING)))
     FROM UNNEST(event_params) WHERE key = 'session_engaged')            AS session_engaged,
  device.category                                                        AS device_category,
  device.operating_system                                                AS operating_system,
  device.web_info.browser                                                AS browser,
  geo.country                                                            AS country,
  traffic_source.source                                                  AS first_user_source,
  traffic_source.medium                                                  AS first_user_medium,
  ecommerce.transaction_id                                               AS transaction_id,
  ecommerce.purchase_revenue_in_usd                                      AS purchase_revenue,
  ecommerce.total_item_quantity                                          AS purchase_units,
  items
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131';


-- -----------------------------------------------------------------------------
-- 2. fact_session | one row per session
-- Dimensions come from the session's first event. Step flags are 0/1 integers
-- so Looker Studio can SUM them directly.
--   session_<step>  = presence funnel (the brief's definition)
--   ordered_<step>  = strict in-order funnel (each step at/after the previous)
-- Sessions are dated by their FIRST event, so a session crossing midnight is
-- counted once (the brief's daily Q01 counts it on both days).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE ga4_portfolio.fact_session
CLUSTER BY session_date, device_category, country
AS
WITH per_session AS (
  SELECT
    session_key,
    ANY_VALUE(user_pseudo_id)                                  AS user_pseudo_id,
    ANY_VALUE(ga_session_id)                                   AS ga_session_id,
    ARRAY_AGG(
      STRUCT(event_date, device_category, operating_system, browser, country,
             first_user_source, first_user_medium)
      ORDER BY event_timestamp LIMIT 1)[OFFSET(0)]             AS first_event,
    ARRAY_AGG(IF(event_name = 'page_view', page_location, NULL) IGNORE NULLS
              ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS landing_page,
    LOGICAL_OR(session_engaged = '1')                          AS is_engaged,
    LOGICAL_OR(event_name = 'session_start')                   AS has_session_start,
    LOGICAL_OR(event_name = 'first_visit')                     AS is_first_visit,
    COUNT(*)                                                   AS events,
    COUNTIF(event_name = 'page_view')                          AS page_views,
    LOGICAL_OR(event_name = 'view_item')                       AS has_view_item,
    LOGICAL_OR(event_name = 'add_to_cart')                     AS has_add_to_cart,
    LOGICAL_OR(event_name = 'begin_checkout')                  AS has_begin_checkout,
    LOGICAL_OR(event_name = 'add_shipping_info')               AS has_add_shipping,
    LOGICAL_OR(event_name = 'add_payment_info')                AS has_add_payment,
    LOGICAL_OR(event_name = 'purchase')                        AS has_purchase,
    COUNTIF(event_name = 'purchase')                           AS purchase_events,
    SUM(IF(event_name = 'purchase', purchase_revenue, 0))      AS purchase_revenue,
    SUM(IF(event_name = 'purchase', purchase_units, 0))        AS purchase_units,
    MIN(IF(event_name = 'begin_checkout', event_timestamp, NULL)) AS checkout_ts,
    ARRAY_AGG(IF(event_name = 'add_shipping_info', event_timestamp, NULL) IGNORE NULLS) AS shipping_times,
    ARRAY_AGG(IF(event_name = 'add_payment_info',  event_timestamp, NULL) IGNORE NULLS) AS payment_times,
    ARRAY_AGG(IF(event_name = 'purchase',          event_timestamp, NULL) IGNORE NULLS) AS purchase_times
  FROM ga4_portfolio.stg_events
  WHERE session_key IS NOT NULL
  GROUP BY session_key
),
-- Walk the checkout steps in order. ">=" keeps events logged with the same
-- timestamp; ">" would wrongly drop them.
step_shipping AS (
  SELECT *, (SELECT MIN(t) FROM UNNEST(shipping_times) AS t WHERE t >= checkout_ts) AS shipping_ts
  FROM per_session
),
step_payment AS (
  SELECT *, (SELECT MIN(t) FROM UNNEST(payment_times) AS t WHERE t >= shipping_ts) AS payment_ts
  FROM step_shipping
),
step_purchase AS (
  SELECT *, (SELECT MIN(t) FROM UNNEST(purchase_times) AS t WHERE t >= payment_ts) AS ordered_purchase_ts
  FROM step_payment
)
SELECT
  session_key,
  user_pseudo_id,
  ga_session_id,
  first_event.event_date                                AS session_date,
  first_event.device_category                           AS device_category,
  first_event.operating_system                          AS operating_system,
  first_event.browser                                   AS browser,
  first_event.country                                   AS country,
  first_event.first_user_source                         AS first_user_source,
  first_event.first_user_medium                         AS first_user_medium,
  COALESCE(landing_page, '(no page view)')              AS landing_page,

  1                                                     AS sessions,          -- SUM(sessions) = session count
  CAST(IFNULL(is_engaged, FALSE) AS INT64)              AS engaged_session,
  CAST(has_session_start AS INT64)                      AS started_session,
  CAST(is_first_visit AS INT64)                         AS new_user_session,
  events,
  page_views,

  -- Presence funnel (brief definition)
  CAST(has_view_item      AS INT64)                     AS session_view_item,
  CAST(has_add_to_cart    AS INT64)                     AS session_add_to_cart,
  CAST(has_begin_checkout AS INT64)                     AS session_begin_checkout,
  CAST(has_add_shipping   AS INT64)                     AS session_add_shipping,
  CAST(has_add_payment    AS INT64)                     AS session_add_payment,
  CAST(has_purchase       AS INT64)                     AS session_purchase,

  -- Ordered checkout funnel
  CAST(checkout_ts IS NOT NULL         AS INT64)        AS ordered_checkout,
  CAST(shipping_ts IS NOT NULL         AS INT64)        AS ordered_shipping,
  CAST(payment_ts IS NOT NULL          AS INT64)        AS ordered_payment,
  CAST(ordered_purchase_ts IS NOT NULL AS INT64)        AS ordered_purchase,
  IF(ordered_purchase_ts IS NOT NULL,
     ROUND((ordered_purchase_ts - checkout_ts) / 60e6, 2), NULL) AS minutes_checkout_to_purchase,

  purchase_events,
  purchase_revenue,
  purchase_units
FROM step_purchase;


-- -----------------------------------------------------------------------------
-- 3. fact_order | one row per purchase event
-- valid_transaction_id is NULL for placeholder IDs, so
-- COUNT_DISTINCT(valid_transaction_id) = transactions.
-- is_duplicate_transaction flags the 2nd+ event of a repeated transaction ID.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE ga4_portfolio.fact_order
CLUSTER BY order_date, device_category
AS
WITH purchases AS (
  SELECT
    event_date                                              AS order_date,
    event_timestamp,
    session_key,
    user_pseudo_id,
    device_category,
    country,
    first_user_source,
    first_user_medium,
    transaction_id,
    IF(transaction_id IS NULL
         OR LOWER(transaction_id) IN ('(not set)', '(data deleted)', '<other>'),
       NULL, transaction_id)                                AS valid_transaction_id,
    purchase_revenue,
    purchase_units
  FROM ga4_portfolio.stg_events
  WHERE event_name = 'purchase'
)
SELECT
  *,
  1                                                         AS purchase_events,
  CAST(valid_transaction_id IS NOT NULL
       AND ROW_NUMBER() OVER (PARTITION BY valid_transaction_id
                              ORDER BY event_timestamp, session_key) > 1
       AS INT64)                                            AS is_duplicate_transaction
FROM purchases;


-- -----------------------------------------------------------------------------
-- 4. fact_event_user_daily | one row per day x event x user x dimensions
-- Small enough for Looker, but keeps user_pseudo_id so
-- COUNT_DISTINCT(user_pseudo_id) gives correct active users under any filter.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE ga4_portfolio.fact_event_user_daily
CLUSTER BY event_date, event_name
AS
SELECT
  event_date,
  event_name,
  user_pseudo_id,
  device_category,
  operating_system,
  browser,
  country,
  first_user_source,
  first_user_medium,
  COUNT(*) AS event_count
FROM ga4_portfolio.stg_events
GROUP BY event_date, event_name, user_pseudo_id, device_category, operating_system,
         browser, country, first_user_source, first_user_medium;


-- -----------------------------------------------------------------------------
-- 5. fact_page | one row per page_view event
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE ga4_portfolio.fact_page
CLUSTER BY event_date, page_url_clean
AS
SELECT
  event_date,
  event_timestamp,
  session_key,
  user_pseudo_id,
  device_category,
  country,
  COALESCE(page_location, '(missing URL)')                    AS page_url,
  COALESCE(
    NULLIF(REGEXP_REPLACE(REGEXP_REPLACE(page_location, r'[?#].*$', ''), r'/$', ''), ''),
    '(missing URL)')                                          AS page_url_clean,
  COALESCE(page_title, '(no title)')                          AS page_title,
  1                                                           AS page_views
FROM ga4_portfolio.stg_events
WHERE event_name = 'page_view';


-- -----------------------------------------------------------------------------
-- 6. fact_item | one row per product inside a product event
-- Entry flags are 0/1, so SUM(view_entry) = the brief's "views", etc.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE ga4_portfolio.fact_item
CLUSTER BY event_date, item_name
AS
SELECT
  e.event_date,
  e.event_name,
  e.session_key,
  e.user_pseudo_id,
  e.device_category,
  e.country,
  item.item_id,
  item.item_name,
  item.item_category,
  item.price_in_usd,
  item.quantity,
  CAST(e.event_name = 'view_item'      AS INT64)                       AS view_entry,
  CAST(e.event_name = 'add_to_cart'    AS INT64)                       AS cart_entry,
  CAST(e.event_name = 'begin_checkout' AS INT64)                       AS checkout_entry,
  CAST(e.event_name = 'purchase'       AS INT64)                       AS purchase_entry,
  IF(e.event_name = 'purchase', item.quantity, 0)                      AS units_purchased,
  IF(e.event_name = 'purchase', item.price_in_usd * item.quantity, 0)  AS item_revenue,
  IF(e.event_name = 'purchase', item.item_revenue_in_usd, 0)           AS reported_item_revenue
FROM ga4_portfolio.stg_events AS e,
     UNNEST(e.items) AS item
WHERE e.event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase');


-- -----------------------------------------------------------------------------
-- 7. dim_user | one row per user
-- is_first_time_purchaser: first visit is inside the period AND purchased.
-- (Data starts 2020-11-01, so these users cannot have bought before.)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE ga4_portfolio.dim_user
CLUSTER BY first_user_source, first_user_medium
AS
WITH per_user AS (
  SELECT
    user_pseudo_id,
    MIN(event_date)                                                     AS first_seen_date,
    ARRAY_AGG(STRUCT(first_user_source, first_user_medium, device_category, country)
              ORDER BY event_timestamp LIMIT 1)[OFFSET(0)]              AS first_event,
    LOGICAL_OR(event_name = 'first_visit')                              AS has_first_visit,
    LOGICAL_OR(event_name = 'purchase')                                 AS has_purchase,
    MIN(IF(event_name = 'purchase', event_date, NULL))                  AS first_purchase_date,
    COUNTIF(event_name = 'purchase')                                    AS purchase_events,
    SUM(IF(event_name = 'purchase', purchase_revenue, 0))               AS purchase_revenue
  FROM ga4_portfolio.stg_events
  WHERE user_pseudo_id IS NOT NULL
  GROUP BY user_pseudo_id
)
SELECT
  user_pseudo_id,
  first_seen_date,
  first_event.first_user_source                          AS first_user_source,
  first_event.first_user_medium                          AS first_user_medium,
  first_event.device_category                            AS first_device_category,
  first_event.country                                    AS first_country,
  1                                                      AS users,              -- SUM(users) = user count
  CAST(has_first_visit AS INT64)                         AS is_new_user,
  CAST(has_purchase AS INT64)                            AS is_purchaser,
  first_purchase_date,
  CAST(has_first_visit AND has_purchase AS INT64)        AS is_first_time_purchaser,
  purchase_events,
  purchase_revenue
FROM per_user;


-- =============================================================================
-- QA | Run after the build. Every *_ok column should be TRUE.
-- =============================================================================
SELECT
  -- Nothing lost between raw and staging
  (SELECT COUNT(*) FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
     WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131')
    = (SELECT COUNT(*) FROM ga4_portfolio.stg_events)                      AS stg_row_count_ok,

  -- Event totals preserved in the daily user table
  (SELECT SUM(event_count) FROM ga4_portfolio.fact_event_user_daily)
    = (SELECT COUNT(*) FROM ga4_portfolio.stg_events)                      AS event_totals_ok,

  -- One row per session key
  (SELECT COUNT(*) = COUNT(DISTINCT session_key) FROM ga4_portfolio.fact_session) AS session_grain_ok,

  -- Ordered funnel never increases
  (SELECT LOGICAL_AND(ordered_shipping <= ordered_checkout
                      AND ordered_payment <= ordered_shipping
                      AND ordered_purchase <= ordered_payment)
     FROM ga4_portfolio.fact_session)                                      AS ordered_funnel_ok,

  -- Page views and purchases preserved
  (SELECT COUNT(*) FROM ga4_portfolio.fact_page)
    = (SELECT COUNTIF(event_name = 'page_view') FROM ga4_portfolio.stg_events) AS page_views_ok,
  (SELECT COUNT(*) FROM ga4_portfolio.fact_order)
    = (SELECT COUNTIF(event_name = 'purchase') FROM ga4_portfolio.stg_events)  AS orders_ok,

  -- One row per user
  (SELECT COUNT(*) = COUNT(DISTINCT user_pseudo_id) FROM ga4_portfolio.dim_user) AS user_grain_ok;

-- Cross-check against the analysis queries (should match closely):
--   SELECT device_category, SUM(session_begin_checkout), SUM(session_add_shipping),
--          SUM(session_add_payment), SUM(session_purchase)
--   FROM ga4_portfolio.fact_session GROUP BY device_category;      -- vs Q10
--   SELECT first_user_source, first_user_medium, SUM(started_session)
--   FROM ga4_portfolio.fact_session GROUP BY 1, 2 ORDER BY 3 DESC;  -- vs Q03
