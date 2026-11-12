-- =============================================================================
-- Q07 | How are active users distributed across operating systems and browsers?
-- Source : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- Grain  : one row per operating system x browser, whole period
--          (2020-11-01 to 2021-01-31)
--
-- Definitions (as in the brief):
--   active_users = distinct user_pseudo_id seen on that OS + browser pair
--
-- Expected check (brief): Web / Chrome 113,813 | Web / Safari 32,758 |
--   iOS / Safari 28,724 | Windows / Chrome 27,887 | Android / Chrome 21,056 |
--   Macintosh / Chrome 15,114
--
-- Note: 'Web' is not a real operating system. In this sample a large share of
-- traffic carries 'Web' instead of an OS name (most likely from Google's
-- anonymisation of the dataset), so that row probably mixes Windows, Mac,
-- Linux and others. Say this when presenting the chart, and use Part B
-- (browser only) for a cleaner comparison.
-- =============================================================================

WITH by_os_browser AS (
  SELECT
    device.operating_system         AS os,
    device.web_info.browser         AS browser,
    COUNT(DISTINCT user_pseudo_id)  AS active_users
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY os, browser
),

total AS (
  SELECT COUNT(DISTINCT user_pseudo_id) AS total_users
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
)

SELECT
  b.os,
  b.browser,
  b.active_users,
  ROUND(100 * SAFE_DIVIDE(b.active_users, t.total_users), 2) AS pct_of_users
FROM by_os_browser AS b
CROSS JOIN total AS t
ORDER BY b.active_users DESC, b.os, b.browser;


-- =============================================================================
-- Part B (optional) | Browser only, ignoring the OS
-- Avoids the 'Web' placeholder problem. A user on Chrome under both 'Web' and
-- 'Windows' is counted once here.
-- =============================================================================
WITH by_browser AS (
  SELECT
    device.web_info.browser        AS browser,
    COUNT(DISTINCT user_pseudo_id) AS active_users
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY browser
),
total AS (
  SELECT COUNT(DISTINCT user_pseudo_id) AS total_users
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
)
SELECT
  b.browser,
  b.active_users,
  ROUND(100 * SAFE_DIVIDE(b.active_users, t.total_users), 2) AS pct_of_users
FROM by_browser AS b
CROSS JOIN total AS t
ORDER BY b.active_users DESC;


-- =============================================================================
-- Part C (optional) | Which OS + browser pairs convert best?
-- Useful for QA teams: a pair with plenty of traffic but a much lower purchase
-- rate than its peers can point to a checkout bug on that platform.
-- Pairs with fewer than 1,000 sessions are excluded to avoid noisy rates.
-- =============================================================================
WITH events AS (
  SELECT
    device.operating_system  AS os,
    device.web_info.browser  AS browser,
    user_pseudo_id,
    event_name,
    CONCAT(
      user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_key
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
by_pair AS (
  SELECT
    os,
    browser,
    COUNT(DISTINCT user_pseudo_id)                                       AS active_users,
    COUNT(DISTINCT session_key)                                          AS sessions,
    COUNT(DISTINCT IF(event_name = 'begin_checkout', session_key, NULL)) AS checkout_sessions,
    COUNT(DISTINCT IF(event_name = 'purchase', session_key, NULL))       AS purchase_sessions
  FROM events
  GROUP BY os, browser
)
SELECT
  os,
  browser,
  active_users,
  sessions,
  checkout_sessions,
  purchase_sessions,
  ROUND(SAFE_DIVIDE(purchase_sessions, sessions), 4)          AS purchase_rate,
  ROUND(SAFE_DIVIDE(purchase_sessions, checkout_sessions), 4) AS checkout_completion_rate
FROM by_pair
WHERE sessions >= 1000          -- minimum volume; adjust and state it in your write-up
ORDER BY sessions DESC;


-- =============================================================================
-- QA | How many user IDs appear under more than one OS + browser pair?
-- If the number is large, rows overlap and should not be added together.
-- =============================================================================
-- SELECT COUNT(*) AS users_on_multiple_pairs
-- FROM (
--   SELECT user_pseudo_id
--   FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--   WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--   GROUP BY user_pseudo_id
--   HAVING COUNT(DISTINCT CONCAT(IFNULL(device.operating_system, ''), '|',
--                                IFNULL(device.web_info.browser, ''))) > 1
-- );


-- =============================================================================
-- Dashboard tip (Looker Studio): a table or treemap with OS and Browser as
-- dimensions and COUNT_DISTINCT(user_pseudo_id) as the metric works well.
-- Limit it to the top 10 pairs; the long tail of rare combinations adds noise.
-- =============================================================================
