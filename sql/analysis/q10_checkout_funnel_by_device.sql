-- =============================================================================
-- Q10 | For each device category, how many sessions complete each checkout
--       step: begin checkout -> add shipping -> add payment -> purchase?
-- Source : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- Grain  : one row per device_category, whole period (2020-11-01 to 2021-01-31)
--
-- Definitions (as in the brief):
--   session_key           = user_pseudo_id + '-' + ga_session_id
--   session_<step>        = distinct sessions that fired that step's event
--   add_payment_rate      = session_add_payment / session_begin_checkout
--   purchase_rate         = session_purchase / session_add_payment
--
-- Expected check (brief):
--   desktop 6,392 | 6,390 | 3,885 | 2,749 | 0.61 | 0.71
--   mobile  4,474 | 4,475 | 2,778 | 1,995 | 0.62 | 0.72
--   tablet    240 |   240 |   152 |   104 | 0.63 | 0.68
--
-- Note: this is a PRESENCE funnel. A session counts at a step if the event
-- happened at all, in any order. That is why mobile shows more shipping
-- sessions (4,475) than checkout sessions (4,474). Part B builds a strict,
-- in-order funnel for comparison.
-- =============================================================================

WITH checkout_events AS (
  SELECT
    device.category AS device_category,
    event_name,
    CONCAT(
      user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_key
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name IN ('begin_checkout', 'add_shipping_info', 'add_payment_info', 'purchase')
),

by_device AS (
  SELECT
    device_category,
    COUNT(DISTINCT IF(event_name = 'begin_checkout',    session_key, NULL)) AS session_begin_checkout,
    COUNT(DISTINCT IF(event_name = 'add_shipping_info', session_key, NULL)) AS session_add_shipping,
    COUNT(DISTINCT IF(event_name = 'add_payment_info',  session_key, NULL)) AS session_add_payment,
    COUNT(DISTINCT IF(event_name = 'purchase',          session_key, NULL)) AS session_purchase
  FROM checkout_events
  GROUP BY device_category
)

SELECT
  device_category,
  session_begin_checkout,
  session_add_shipping,
  session_add_payment,
  session_purchase,
  ROUND(SAFE_DIVIDE(session_add_payment, session_begin_checkout), 2) AS add_payment_rate,
  ROUND(SAFE_DIVIDE(session_purchase, session_add_payment), 2)       AS purchase_rate,

  -- Extras: the step the brief skips, and the end-to-end rate
  ROUND(SAFE_DIVIDE(session_add_shipping, session_begin_checkout), 2) AS add_shipping_rate,
  ROUND(SAFE_DIVIDE(session_purchase, session_begin_checkout), 2)     AS checkout_completion_rate
FROM by_device
ORDER BY session_begin_checkout DESC;


-- =============================================================================
-- Part B (optional) | Strict, in-order funnel with drop-off and timing
-- A session reaches a step only if that event happens AT OR AFTER the previous
-- step it reached. ">=" (not ">") is used because GA4 can log events from the
-- same batch with identical timestamps; strict ">" would wrongly drop them.
-- Device = device of the session's first checkout-path event.
--   exits_<step>         = sessions that reached the previous step but not this one
--   median_mins_to_buy   = median minutes from begin_checkout to purchase
-- =============================================================================
WITH checkout_events AS (
  SELECT
    device.category AS device_category,
    event_name,
    event_timestamp,                                   -- microseconds since epoch
    CONCAT(
      user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_key
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name IN ('begin_checkout', 'add_shipping_info', 'add_payment_info', 'purchase')
),

per_session AS (
  SELECT
    session_key,
    ARRAY_AGG(device_category IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS device_category,
    MIN(IF(event_name = 'begin_checkout', event_timestamp, NULL))                  AS checkout_ts,
    ARRAY_AGG(IF(event_name = 'add_shipping_info', event_timestamp, NULL) IGNORE NULLS) AS shipping_times,
    ARRAY_AGG(IF(event_name = 'add_payment_info',  event_timestamp, NULL) IGNORE NULLS) AS payment_times,
    ARRAY_AGG(IF(event_name = 'purchase',          event_timestamp, NULL) IGNORE NULLS) AS purchase_times
  FROM checkout_events
  WHERE session_key IS NOT NULL
  GROUP BY session_key
),

-- Walk the steps in order: each step looks only at events after the step before.
step_shipping AS (
  SELECT *,
    (SELECT MIN(t) FROM UNNEST(shipping_times) AS t WHERE t >= checkout_ts) AS shipping_ts
  FROM per_session
),
step_payment AS (
  SELECT *,
    (SELECT MIN(t) FROM UNNEST(payment_times) AS t WHERE t >= shipping_ts) AS payment_ts
  FROM step_shipping
),
step_purchase AS (
  SELECT *,
    (SELECT MIN(t) FROM UNNEST(purchase_times) AS t WHERE t >= payment_ts) AS purchase_ts
  FROM step_payment
),

ordered AS (
  SELECT
    COALESCE(device_category, '(unknown)')  AS device_category,
    COUNTIF(checkout_ts IS NOT NULL)        AS reached_checkout,
    COUNTIF(shipping_ts IS NOT NULL)        AS reached_shipping,
    COUNTIF(payment_ts  IS NOT NULL)        AS reached_payment,
    COUNTIF(purchase_ts IS NOT NULL)        AS reached_purchase,
    APPROX_QUANTILES(
      IF(purchase_ts IS NOT NULL, (purchase_ts - checkout_ts) / 60e6, NULL), 100
    )[OFFSET(50)]                            AS median_mins_to_buy
  FROM step_purchase
  GROUP BY device_category
)

SELECT
  device_category,
  reached_checkout,
  reached_shipping,
  reached_payment,
  reached_purchase,
  reached_checkout - reached_shipping                         AS exits_at_shipping,
  reached_shipping - reached_payment                          AS exits_at_payment,
  reached_payment  - reached_purchase                         AS exits_at_purchase,
  ROUND(SAFE_DIVIDE(reached_shipping, reached_checkout), 4)   AS shipping_step_rate,
  ROUND(SAFE_DIVIDE(reached_payment,  reached_shipping), 4)   AS payment_step_rate,
  ROUND(SAFE_DIVIDE(reached_purchase, reached_payment), 4)    AS purchase_step_rate,
  ROUND(SAFE_DIVIDE(reached_purchase, reached_checkout), 4)   AS checkout_completion_rate,
  ROUND(median_mins_to_buy, 1)                                AS median_mins_to_buy
FROM ordered
ORDER BY reached_checkout DESC;
-- Read it as: the step with the largest exits (and lowest step rate) is the
-- biggest leak. Compare devices at that step; a device that is much worse
-- there points to a device-specific UX or payment problem.


-- =============================================================================
-- QA 1 | Ordered counts must never increase from one step to the next.
-- Expected output: zero rows. (Run against Part B by wrapping it as a CTE.)
--   WHERE reached_shipping > reached_checkout
--      OR reached_payment  > reached_shipping
--      OR reached_purchase > reached_payment
-- =============================================================================


-- =============================================================================
-- QA 2 | How often do consecutive steps share the exact same timestamp?
-- If this number is large, it confirms why Part B uses ">=" instead of ">".
-- =============================================================================
-- WITH e AS (
--   SELECT
--     CONCAT(user_pseudo_id, '-', CAST((SELECT value.int_value FROM UNNEST(event_params)
--            WHERE key = 'ga_session_id') AS STRING)) AS session_key,
--     event_name, event_timestamp
--   FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--   WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--     AND event_name IN ('begin_checkout', 'add_shipping_info')
-- )
-- SELECT COUNT(DISTINCT c.session_key) AS sessions_with_tied_checkout_and_shipping
-- FROM e AS c
-- JOIN e AS s
--   ON  c.session_key = s.session_key
--   AND c.event_name = 'begin_checkout'
--   AND s.event_name = 'add_shipping_info'
--   AND c.event_timestamp = s.event_timestamp;


-- =============================================================================
-- Dashboard tip (Looker Studio): use a funnel or bar chart with the four step
-- counts per device, and build the step rates as calculated fields so they
-- recalculate under date and device filters. Show presence and in-order
-- counts side by side only if you explain the difference on the page.
-- =============================================================================
