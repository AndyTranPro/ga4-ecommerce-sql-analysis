-- =============================================================================
-- Q08 | Which pages receive the most views, and how many active users visit
--       each one?
-- Source : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- Grain  : one row per page URL, whole period (2020-11-01 to 2021-01-31)
--
-- Definitions (as in the brief):
--   page_path    = page_location parameter of the page_view event (full URL)
--   views        = count of page_view events
--   active_users = distinct user_pseudo_id who viewed that URL
--
-- Expected check (brief):
--   https://shop.googlemerchandisestore.com/                     183,074 | 93,511
--   https://shop.googlemerchandisestore.com/Google+Redesign/Apparel  81,681 | 50,193
--   https://shop.googlemerchandisestore.com/basket.html           78,876 | 22,720
--
-- Notes:
--   * page_location is the full URL, including any ?query or #fragment, so the
--     same page can be split across many rows. Part B normalises this.
--   * Page views with no page_location are kept as '(missing URL)' so the
--     total still matches the number of page_view events.
-- =============================================================================

WITH page_views AS (
  SELECT
    user_pseudo_id,
    COALESCE(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
      '(missing URL)'
    ) AS page_path
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'page_view'
)

SELECT
  page_path,
  COUNT(*)                                              AS views,
  COUNT(DISTINCT user_pseudo_id)                        AS active_users,
  ROUND(SAFE_DIVIDE(COUNT(*), COUNT(DISTINCT user_pseudo_id)), 2) AS views_per_user
FROM page_views
GROUP BY page_path
ORDER BY views DESC;


-- =============================================================================
-- Part B (optional) | Same report on a cleaned URL
-- Strips ?query strings and #fragments, and the trailing slash, so variants
-- such as '/basket.html?ref=x' and '/basket.html' are combined. The host is
-- kept because the site uses two domains (shop.googlemerchandisestore.com and
-- googlemerchandisestore.com). Numbers will be higher than the brief's.
-- =============================================================================
WITH page_views AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_title')    AS page_title
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'page_view'
),
cleaned AS (
  SELECT
    user_pseudo_id,
    page_title,
    COALESCE(
      NULLIF(REGEXP_REPLACE(REGEXP_REPLACE(page_location, r'[?#].*$', ''), r'/$', ''), ''),
      '(missing URL)'
    ) AS page_url_clean
  FROM page_views
)
SELECT
  page_url_clean,
  ANY_VALUE(page_title)          AS example_page_title,   -- a readable label for charts
  COUNT(*)                       AS views,
  COUNT(DISTINCT user_pseudo_id) AS active_users
FROM cleaned
GROUP BY page_url_clean
ORDER BY views DESC;


-- =============================================================================
-- Part C (optional) | Landing pages and bounce rate
-- Answers the guide's Engagement question: "which pages make users leave?"
--   landing_page    = URL of the first page_view in the session
--   engaged session = any event in the session has session_engaged = '1'
--                     (GA4: lasted 10s+, had a conversion, or 2+ page views)
--   bounce_rate     = 1 - engaged_sessions / sessions   (GA4 definition)
-- Landing pages with fewer than 500 sessions are excluded to avoid noisy rates.
-- =============================================================================
WITH events AS (
  SELECT
    event_name,
    event_timestamp,
    CONCAT(
      user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_key,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    -- session_engaged can be stored as a string or an integer depending on the event
    (SELECT COALESCE(value.string_value, CAST(value.int_value AS STRING))
       FROM UNNEST(event_params) WHERE key = 'session_engaged') AS session_engaged
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
sessions AS (
  SELECT
    session_key,
    -- First page viewed in the session. IGNORE NULLS skips page views without
    -- a URL; SAFE_OFFSET returns NULL if the session had no page view at all.
    ARRAY_AGG(IF(event_name = 'page_view', page_location, NULL) IGNORE NULLS
              ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS landing_page,
    LOGICAL_OR(session_engaged = '1')                            AS is_engaged
  FROM events
  WHERE session_key IS NOT NULL
  GROUP BY session_key
)
SELECT
  COALESCE(landing_page, '(no page view)')                        AS landing_page,
  COUNT(*)                                                        AS sessions,
  COUNTIF(is_engaged)                                             AS engaged_sessions,
  ROUND(1 - SAFE_DIVIDE(COUNTIF(is_engaged), COUNT(*)), 4)        AS bounce_rate
FROM sessions
GROUP BY landing_page
HAVING COUNT(*) >= 500           -- minimum volume; adjust and state it in your write-up
ORDER BY sessions DESC;
-- Read it as: high-traffic landing pages with a bounce rate well above the site
-- average are the first pages to improve.


-- =============================================================================
-- QA 1 | Page views without a URL, and total page views
-- views summed over the main query must equal total_page_views.
-- =============================================================================
-- SELECT
--   COUNT(*) AS total_page_views,
--   COUNTIF((SELECT value.string_value FROM UNNEST(event_params)
--            WHERE key = 'page_location') IS NULL) AS missing_url
-- FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
-- WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--   AND event_name = 'page_view';


-- =============================================================================
-- QA 2 | How is session_engaged stored in this sample?
-- Confirms the value used in Part C. Expect mostly '1' (and some '0' or NULL).
-- =============================================================================
-- SELECT p.value.string_value, p.value.int_value, COUNT(*) AS events
-- FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`, UNNEST(event_params) AS p
-- WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--   AND p.key = 'session_engaged'
-- GROUP BY 1, 2
-- ORDER BY events DESC;


-- =============================================================================
-- Dashboard tip (Looker Studio): show a Top 10 table by views, with the page
-- title as the label rather than the full URL (long URLs crowd the chart).
-- =============================================================================
