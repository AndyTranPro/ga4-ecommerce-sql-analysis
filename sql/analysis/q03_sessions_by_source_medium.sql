-- =============================================================================
-- Q03 | Which traffic sources and mediums generate the most sessions,
--       and what share of all sessions does each represent?
-- Source : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- Grain  : one row per source x medium, whole period (2020-11-01 to 2021-01-31)
--
-- Definitions (as in the brief):
--   session_key   = user_pseudo_id + '-' + ga_session_id
--   sessions      = distinct session keys on session_start events
--   pct_sessions  = sessions / total sessions x 100 (2 decimals, as in the brief)
--
-- Expected check (brief): google / organic -> 111,488 sessions, 31.42%
--                         (direct) / (none) -> 82,362 sessions, 23.21%
--
-- IMPORTANT interpretation note:
--   traffic_source.* in the GA4 BigQuery export is the source/medium that FIRST
--   acquired the user, not the source of each session. So this table reads as
--   "sessions from users first acquired via X". A user first acquired by
--   google/organic who later returns via an email link is still counted under
--   google/organic. The output columns keep the brief's names, but in a
--   dashboard label them "First user source / medium".
-- =============================================================================

WITH session_starts AS (
  SELECT
    traffic_source.source AS session_source,
    traffic_source.medium AS session_medium,
    CONCAT(
      user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_key                                   -- NULL if either part is missing
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'session_start'
),

by_source AS (
  SELECT
    session_source,
    session_medium,
    COUNT(DISTINCT session_key) AS sessions          -- duplicate session_start events count once
  FROM session_starts
  GROUP BY session_source, session_medium
)

SELECT
  session_source,
  session_medium,
  sessions,
  ROUND(100 * SAFE_DIVIDE(sessions, SUM(sessions) OVER ()), 2) AS pct_sessions
FROM by_source
ORDER BY sessions DESC;


-- =============================================================================
-- Part B (optional) | Roll up to medium (channel-style view)
-- Easier to read on a dashboard than 12 source/medium pairs. Values such as
-- '<Other>' and '(data deleted)' are obfuscation placeholders in this sample,
-- not real channels, so they are grouped as "Unknown / obfuscated".
-- =============================================================================
WITH session_starts AS (
  SELECT
    traffic_source.medium AS medium,
    CONCAT(
      user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_key
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'session_start'
),
by_medium AS (
  SELECT
    CASE
      WHEN medium = 'organic'  THEN 'Organic search'
      WHEN medium = 'cpc'      THEN 'Paid search'
      WHEN medium = 'referral' THEN 'Referral'
      WHEN medium = '(none)'   THEN 'Direct'
      ELSE 'Unknown / obfuscated'
    END AS channel,
    COUNT(DISTINCT session_key) AS sessions
  FROM session_starts
  GROUP BY channel
)
SELECT
  channel,
  sessions,
  ROUND(100 * SAFE_DIVIDE(sessions, SUM(sessions) OVER ()), 2) AS pct_sessions
FROM by_medium
ORDER BY sessions DESC;


-- =============================================================================
-- QA 1 | Shares add to 100 and no sessions are lost.
-- Expected: pct_total = 100.00 (+/- rounding); sessions_in_table = all_sessions.
-- (If the counts differ, the gap is session keys repeated under two labels.)
-- =============================================================================
-- WITH s AS (
--   SELECT
--     traffic_source.source AS src, traffic_source.medium AS med,
--     CONCAT(user_pseudo_id, '-', CAST((SELECT value.int_value FROM UNNEST(event_params)
--            WHERE key = 'ga_session_id') AS STRING)) AS session_key
--   FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--   WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--     AND event_name = 'session_start'
-- )
-- SELECT
--   (SELECT SUM(n) FROM (SELECT COUNT(DISTINCT session_key) AS n FROM s GROUP BY src, med)) AS sessions_in_table,
--   COUNT(DISTINCT session_key)                                                            AS all_sessions,
--   COUNTIF(session_key IS NULL)                                                           AS starts_missing_key
-- FROM s;


-- =============================================================================
-- QA 2 | Is a true session-level source available? Lists the event_params keys
-- found on session_start events. If 'source' / 'medium' appear here, you could
-- build session-level attribution; if not, first-user source is all you have.
-- =============================================================================
-- SELECT p.key, COUNT(*) AS events
-- FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`, UNNEST(event_params) AS p
-- WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--   AND event_name = 'session_start'
-- GROUP BY p.key
-- ORDER BY events DESC;


-- =============================================================================
-- Dashboard tip (Looker Studio): use source, medium and sessions as the source
-- and show the share with the chart's "Percent of total" option rather than the
-- hard-coded pct_sessions, so it recalculates under filters.
-- =============================================================================
