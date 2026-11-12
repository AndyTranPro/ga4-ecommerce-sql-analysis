# Looker Studio guide

How to connect the BigQuery tables to Looker Studio and build the 5-tab dashboard.

**Before you start:** run [`sql/dashboard/build_dashboard_tables.sql`](../sql/dashboard/build_dashboard_tables.sql) in BigQuery, and check that every QA column at the end returns `TRUE`.

---

## 1. Connect the tables

Do this once for each table you need. The main ones are `fact_session`, `fact_order`, `fact_event_user_daily`, `fact_page`, `fact_item` and `dim_user`.

1. Go to [lookerstudio.google.com](https://lookerstudio.google.com) and sign in with the Google account that owns your BigQuery project.
2. Click **Create → Data source**.
3. Choose the **BigQuery** connector and authorise it the first time.
4. Pick **My projects → *your project* → `ga4_portfolio` → `fact_session`**, then click **Connect**.
5. On the fields screen:
   - Check the date field's type is **Date** (`session_date`, `order_date` or `event_date`).
   - Set the **Default aggregation** of ID columns (`session_key`, `user_pseudo_id`, `transaction_id`, `ga_session_id`) to **None**.
   - Leave the 0/1 flag columns (`sessions`, `session_purchase` and so on) at **Sum**.
6. Rename the data source (top left) to something clear, such as `GA4 – fact_session`.
7. Repeat for the other tables.

Then click **Create → Report**, choose **Add data → My data sources**, and add all of them.

> **Tip:** under **Resource → Manage added data sources → Edit**, you can add calculated fields to a data source. Fields added there can be reused in every chart that uses that source.

---

## 2. Calculated fields

Never store rates in SQL. Build them as ratios of sums, so they recalculate correctly under any date or device filter. Add these with **Add a field** on each data source.

### On `fact_session`

| Field name | Formula | Format |
|---|---|---|
| Product view rate | `SUM(session_view_item) / SUM(sessions)` | Percent |
| View → cart rate | `SUM(session_add_to_cart) / SUM(session_view_item)` | Percent |
| Cart → purchase rate | `SUM(session_purchase) / SUM(session_add_to_cart)` | Percent |
| Purchase rate | `SUM(session_purchase) / SUM(sessions)` | Percent |
| Revenue per session | `SUM(purchase_revenue) / SUM(sessions)` | Currency (USD) |
| Bounce rate | `1 - SUM(engaged_session) / SUM(sessions)` | Percent |
| Add payment rate (brief) | `SUM(session_add_payment) / SUM(session_begin_checkout)` | Percent |
| Payment → purchase rate (brief) | `SUM(session_purchase) / SUM(session_add_payment)` | Percent |
| Checkout completion (ordered) | `SUM(ordered_purchase) / SUM(ordered_checkout)` | Percent |
| Users | `COUNT_DISTINCT(user_pseudo_id)` | Number |

### On `fact_order`

| Field name | Formula | Format |
|---|---|---|
| Transactions | `COUNT_DISTINCT(valid_transaction_id)` | Number |
| AOV | `SUM(purchase_revenue) / COUNT_DISTINCT(valid_transaction_id)` | Currency (USD) |
| Avg basket size | `SUM(purchase_units) / COUNT_DISTINCT(valid_transaction_id)` | Number |

### On `fact_event_user_daily`

| Field name | Formula | Format |
|---|---|---|
| Active users | `COUNT_DISTINCT(user_pseudo_id)` | Number |

### On `fact_item`

| Field name | Formula | Format |
|---|---|---|
| View → cart rate (item) | `SUM(cart_entry) / SUM(view_entry)` | Percent |
| Cart abandon rate (item) | `1 - SUM(purchase_entry) / SUM(cart_entry)` | Percent |

### On `dim_user`

| Field name | Formula | Format |
|---|---|---|
| Buyer rate | `SUM(is_purchaser) / SUM(users)` | Percent |
| First-time purchasers | `SUM(is_first_time_purchaser)` | Number |

---

## 3. Report-wide controls

Add these on each page, or once on a page and then **Arrange → Make report-level**:

- **Date range control**, defaulting to 1 Nov 2020 – 31 Jan 2021. Each chart filters on its own data source's date field (`session_date`, `order_date` or `event_date`).
- **Drop-down list** on `device_category`, and another on `country`. A control filters charts from other data sources only when the field has the same name and type in each table. Both fields do here, but if a chart doesn't respond, add a separate control for that data source.

---

## 4. The 5 tabs

### Tab 1 – Overview (Q01, Q02)

| Chart | Data source | Setup |
|---|---|---|
| Scorecards | `fact_session` / `fact_order` | Sessions (`SUM(sessions)`), Purchase rate, Revenue (`SUM(purchase_revenue)`), Transactions, AOV |
| Time series | `fact_session` | Dimension `session_date`; metrics Sessions and Purchase rate (put the rate on the right axis) |
| Time series | `fact_order` | Dimension `order_date`; metrics revenue and AOV |
| Stacked bar (100%) | `fact_event_user_daily` | Dimension `event_date`, breakdown `event_name`, metric `SUM(event_count)` |
| Table | `fact_event_user_daily` | Dimension `event_name`; metrics `SUM(event_count)`, Active users; add a **Percent of total** comparison on `event_count` |

### Tab 2 – Revenue drivers (Q01, Q04, Q09)

| Chart | Data source | Setup |
|---|---|---|
| Table with heatmap | `fact_session` | Dimensions `first_user_source`, `first_user_medium`; metrics Sessions, Purchase rate, Revenue, Revenue per session |
| Bar | `dim_user` | Dimension `first_user_medium`; metric First-time purchasers |
| Table | `fact_item` | Dimension `item_name`; metrics `SUM(item_revenue)` and `SUM(units_purchased)`; sort by revenue; Top 20 |

### Tab 3 – Demographics (Q05–Q07)

| Chart | Data source | Setup |
|---|---|---|
| Donut | `fact_event_user_daily` | Dimension `device_category`; metric Active users |
| Geo chart | `fact_event_user_daily` | Dimension `country` (set its type to **Geo → Country**); metric Active users |
| Table | `fact_event_user_daily` | Dimensions `operating_system`, `browser`; metric Active users; Top 10 |
| Bar | `fact_session` | Dimension `device_category`; metric Purchase rate (shows which device converts best) |

> Explain on the page that `operating_system = 'Web'` is a placeholder in this sample, not a real OS.

### Tab 4 – User behaviour (Q08 + bounce)

| Chart | Data source | Setup |
|---|---|---|
| Table | `fact_page` | Dimension `page_title` (or `page_url_clean`); metrics `SUM(page_views)`, `COUNT_DISTINCT(user_pseudo_id)`; Top 15 |
| Table | `fact_session` | Dimension `landing_page`; metrics Sessions, Bounce rate. Add a chart filter of **Sessions ≥ 500** so tiny pages don't top the list |

### Tab 5 – eCommerce funnel (Q10, Q09)

| Chart | Data source | Setup |
|---|---|---|
| Funnel chart (or horizontal bar) | `fact_session` | Metrics `SUM(ordered_checkout)`, `SUM(ordered_shipping)`, `SUM(ordered_payment)`, `SUM(ordered_purchase)` |
| Table | `fact_session` | Dimension `device_category`; the four `session_*` checkout metrics plus Add payment rate and Payment → purchase rate (the brief's version of Q10) |
| Table | `fact_item` | Dimension `item_name`; metrics `SUM(cart_entry)`, `SUM(purchase_entry)`, Cart abandon rate; filter `SUM(cart_entry) ≥ 500` |

---

## 5. Finishing touches

- Add a short text box at the top of each page that states the question it answers and one key takeaway.
- Add a **Data notes** text box on the Overview page covering the add-to-cart gap before mid-Nov 2020, first-user (not session) source, and the obfuscated values.
- **Share → Manage access → Anyone with the link can view.** Paste that link into the README.
- Take a screenshot of each page, save it in [`/images`](../images) and reference it in the README.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Access denied" when connecting | Use the same Google account as your BigQuery project, and re-authorise the BigQuery connector. |
| Table not listed | Check the build script ran without errors and the dataset is called `ga4_portfolio`. |
| Rate shows a huge number | The field was set to `AVG` or `SUM` of a rate. Rebuild it as a ratio of sums (section 2). |
| Tables vanished after 60 days | BigQuery Sandbox expires tables. Run the build script again. |
| Viewers see "no access" | For a public dashboard, set data credentials to **Owner's credentials** (Resource → Manage added data sources → Edit → Data credentials). |
