-- =============================================================================
-- Q09 | For each product: views, add-to-cart actions, checkouts, units
--       purchased and revenue.
-- Source : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
-- Grain  : one row per item_name, whole period (2020-11-01 to 2021-01-31)
--
-- Definitions (as in the brief, after fixing its swapped hints):
--   views            = item entries in view_item events
--   added_to_cart    = item entries in add_to_cart events
--   checked_out      = item entries in begin_checkout events
--   items_purchased  = SUM(quantity) on purchase events
--   item_revenue     = SUM(price * quantity) on purchase events
--
-- "Item entry" = one product inside an event's items array. An event with three
-- products counts once for each of them, which is what we want per product.
--
-- Expected check (brief):
--   Google Navy Speckled Tee  56,466 | 14,094 | 462 | 178 | 4,440
--   Super G Unisex Joggers    52,758 | 12,015 | 1,185 | 308 | 9,548
--   Google Zip Hoodie F/C     49,795 | 13,011 | 986 | 273 | 13,788
--
-- Notes:
--   * ecommerce/items data is only reliable on these four event types.
--   * add_to_cart is barely tracked before mid-Nov 2020, so cart counts are
--     understated for early November (see Q01/Q02).
-- =============================================================================

WITH item_entries AS (
  SELECT
    e.event_name,
    item.item_name,
    item.quantity,
    item.price_in_usd,
    item.item_revenue_in_usd
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e,
       UNNEST(e.items) AS item                     -- one row per product in the event
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND e.event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
)

SELECT
  item_name,
  COUNTIF(event_name = 'view_item')                                AS views,
  COUNTIF(event_name = 'add_to_cart')                              AS added_to_cart,
  COUNTIF(event_name = 'begin_checkout')                           AS checked_out,
  SUM(IF(event_name = 'purchase', quantity, 0))                    AS items_purchased,
  ROUND(SUM(IF(event_name = 'purchase', price_in_usd * quantity, 0)), 2) AS item_revenue,

  -- Extra: the revenue GA4 itself recorded per item. If it differs a lot from
  -- item_revenue, discounts or missing prices are involved (see QA 2).
  ROUND(SUM(IF(event_name = 'purchase', item_revenue_in_usd, 0)), 2)     AS reported_item_revenue
FROM item_entries
GROUP BY item_name
ORDER BY views DESC;


-- =============================================================================
-- Part B (optional) | Which products are added to cart but not bought?
-- Answers the guide's Product question. Products with fewer than 500 cart adds
-- are excluded so small numbers don't dominate the ranking.
--   view_to_cart_rate    = added_to_cart / views
--   cart_to_purchase_rate= purchase entries / added_to_cart
--   cart_abandon_rate    = 1 - cart_to_purchase_rate
-- Counts are item entries, not sessions, so treat rates as indicators rather
-- than exact funnel conversion.
-- =============================================================================
WITH item_entries AS (
  SELECT e.event_name, item.item_name
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e,
       UNNEST(e.items) AS item
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND e.event_name IN ('view_item', 'add_to_cart', 'purchase')
),
by_item AS (
  SELECT
    item_name,
    COUNTIF(event_name = 'view_item')   AS views,
    COUNTIF(event_name = 'add_to_cart') AS added_to_cart,
    COUNTIF(event_name = 'purchase')    AS purchase_entries
  FROM item_entries
  GROUP BY item_name
)
SELECT
  item_name,
  views,
  added_to_cart,
  purchase_entries,
  ROUND(SAFE_DIVIDE(added_to_cart, views), 4)                AS view_to_cart_rate,
  ROUND(SAFE_DIVIDE(purchase_entries, added_to_cart), 4)     AS cart_to_purchase_rate,
  ROUND(1 - SAFE_DIVIDE(purchase_entries, added_to_cart), 4) AS cart_abandon_rate,
  added_to_cart - purchase_entries                           AS abandoned_cart_adds
FROM by_item
WHERE added_to_cart >= 500        -- minimum volume; adjust and state it in your write-up
ORDER BY abandoned_cart_adds DESC;
-- Rank by abandoned_cart_adds (volume of lost sales), and use cart_abandon_rate
-- to tell a product with a real problem from one that is simply popular.


-- =============================================================================
-- QA 1 | Is item_name a reliable product key?
-- Lists names shared by several item_ids (or placeholder names). If many show
-- up, group by item_id instead and use item_name only as a label.
-- =============================================================================
-- SELECT item.item_name, COUNT(DISTINCT item.item_id) AS item_ids
-- FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e,
--      UNNEST(e.items) AS item
-- WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
--   AND e.event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
-- GROUP BY item.item_name
-- HAVING COUNT(DISTINCT item.item_id) > 1
--     OR item.item_name IN ('(not set)', '(data deleted)', '<Other>')
-- ORDER BY item_ids DESC;


-- =============================================================================
-- QA 2 | Revenue reconciliation on purchase events
-- Compares price * quantity, GA4's item revenue, and order-level revenue.
-- Big gaps mean missing prices, discounts, tax/shipping in order revenue, or
-- purchase events without items.
-- =============================================================================
-- SELECT
--   (SELECT ROUND(SUM(item.price_in_usd * item.quantity), 2)
--      FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e, UNNEST(e.items) AS item
--      WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131' AND e.event_name = 'purchase') AS price_x_qty,
--   (SELECT ROUND(SUM(item.item_revenue_in_usd), 2)
--      FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` AS e, UNNEST(e.items) AS item
--      WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131' AND e.event_name = 'purchase') AS reported_item_revenue,
--   (SELECT ROUND(SUM(ecommerce.purchase_revenue_in_usd), 2)
--      FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--      WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131' AND event_name = 'purchase') AS order_revenue,
--   (SELECT COUNTIF(ARRAY_LENGTH(items) = 0)
--      FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--      WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131' AND event_name = 'purchase') AS purchases_without_items;


-- =============================================================================
-- Dashboard tip (Looker Studio): a table of the Top 20 products by revenue with
-- views, cart adds and units side by side, plus a bar chart of Part B's
-- abandoned_cart_adds, tells the product story on one page.
-- =============================================================================
