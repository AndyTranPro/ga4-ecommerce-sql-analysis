# Findings

Each finding follows the pattern **finding → evidence → recommendation**, with a confidence level.

> **Source of the numbers.** Figures below come from the expected outputs published with the project brief. They were produced by running the brief's queries on the full dataset. Ratios are calculated from those figures. Values marked **[fill in]** need a run of this repo's queries; the query that produces each one is named next to it. Re-check every figure against your own run before presenting.

---

## Summary

| # | Finding | Impact | Confidence |
|---|---|---|---|
| 1 | Payment is the biggest leak in checkout: 4,290 sessions stop between shipping and payment | High | High |
| 2 | The store's own domain is counted as a "referral" channel, so returning buyers are credited to the wrong source | Medium | High |
| 3 | 1 in 5 sessions has no usable acquisition source, which limits any channel ROI analysis | Medium | High |
| 4 | Two top-10 products have more than 21,000 cart adds between them and zero sales | High | Medium |
| 5 | Google organic search is the largest source of new buyers; paid search converts the worst | Medium | Medium |
| 6 | Add-to-cart was barely tracked before ~16 Nov 2020, so early cart metrics are invalid | High (for analysis) | High |
| 7 | Users revisit the basket page far more than other pages, a sign of hesitation before checkout | Low–Medium | Medium |

---

## 1. Payment is the biggest leak in checkout

**Evidence (Q10, all devices combined)**

| Step | Sessions | Step rate | Sessions lost |
|---|---:|---:|---:|
| Begin checkout | 11,106 | – | – |
| Add shipping info | 11,105 | 100.0% | 1 |
| Add payment info | 6,815 | 61.4% | **4,290** |
| Purchase | 4,848 | 71.1% | 1,967 |

- Only **43.7%** of sessions that start checkout end in a purchase.
- The pattern is almost identical on every device: completion is 43.0% on desktop, 44.6% on mobile and 43.3% on tablet. The problem is the payment step itself, not a device-specific layout issue.
- The shipping step equals the checkout step (11,105 vs 11,106). `add_shipping_info` appears to fire automatically with `begin_checkout`, so it isn't a real user step in this data.

**Recommendation**
- Review the payment step first: available payment methods, form validation errors, and costs revealed late (shipping or tax).
- Add tracking for payment errors, and fix `add_shipping_info` so it fires when the user actually submits shipping details.
- Compare the ordered funnel (the `ordered_*` fields in `fact_session`) with these presence counts. The median time from checkout to purchase is **[fill in: Q10 Part B]** minutes.

---

## 2. The store's own domain is counted as a referral source

**Evidence (Q04)**

| First-user source / medium | Purchase events per 1,000 users | Share of purchases from first-time buyers* |
|---|---:|---:|
| shop.googlemerchandisestore.com / referral | **27.7** | **23%** |
| google / organic | 14.2 | 86% |
| (direct) / (none) | 16.7 | 66% |
| Average of the 8 main rows | 17.3 | – |

\* First-time purchasers ÷ purchase events. This mixes users and events, so read it as an indicator only.

- The store's own domain looks like the best-converting "channel", but very few of its buyers are new. These are returning customers whose visits were re-attributed to the store's own site.

**Recommendation**
- Add the store's own domains (and the payment provider's) to GA4's **unwanted referrals** list.
- Don't credit "referral" for these sales in any channel report.

---

## 3. One in five sessions has no usable acquisition source

**Evidence (Q03, 354,857 sessions in total)**
- **20.6%** of sessions have neither a real source nor a real medium (`<Other>` or `(data deleted)`). **33.1%** have no real source.
- The `(data deleted)` group has the highest conversion of all, with 48.9 purchase events per 1,000 users, but only **1** first-time purchaser out of 830 purchases. It is mostly returning customers whose acquisition data was removed.
- For google / cpc (204 vs 166) and `<Other>` / `<Other>` (645 vs 606), first-time purchasers outnumber purchase events. That's impossible if each user had one consistent label, so labels must vary between a user's events (check with Q04 QA 1).

**Recommendation**
- Show the "unknown" share on every channel chart instead of hiding it.
- Don't judge paid-search ROI from this dataset: it has no cost data and a large share of unlabelled traffic.
- Remember that `traffic_source` is the **first-user** source, not the session source.

---

## 4. Two popular products have thousands of cart adds and no sales

**Evidence (Q09)**

| Product | Views | Cart adds | Checkouts | Units sold |
|---|---:|---:|---:|---:|
| Google Women's Striped L/S | 42,142 | 11,847 | 0 | 0 |
| Google F/C Long Sleeve Tee Charcoal | 34,275 | 9,551 | 0 | 0 |

- **21,398 cart adds with no checkout at all.** Other top products convert at least some cart adds into checkouts (1–10%).
- By revenue, Google Zip Hoodie F/C leads the products shown, at $13,788 from 273 units (about $50 per unit). Super G Unisex Joggers follow at $9,548.

**Recommendation**
- Check these two products for stock, checkout eligibility or a broken variant first. Zero checkouts from this many cart adds points to a blocker, not customer choice.
- Feature the high-value apparel (hoodie, joggers) in promotions. Stickers draw many cart adds but earn about $2 per unit.

**Caveat:** across all top products, view→cart sits in a narrow 23–28% band, and product cart adds far exceed product checkouts. Product-level cart data may be inflated in this sample, so confirm it with Q09 QA 1 and QA 2 before presenting it as customer behaviour.

---

## 5. Organic search brings the most new buyers; paid search converts worst

**Evidence (Q03, Q04)**
- google / organic: **31.4%** of sessions and **1,255** first-time purchasers, about **36%** of all first-time purchasers in the main rows.
- google / cpc: 4.4% of sessions and the **lowest** efficiency, at 10.8 purchase events per 1,000 users (average 17.3).

**Recommendation**
- Keep investing in SEO for product and category pages.
- Review paid-search targeting and landing pages. A real ROI judgement needs cost data, which this dataset doesn't include.

---

## 6. Add-to-cart was barely tracked before mid-November 2020

**Evidence (Q01, Q02)**
- 1 Nov 2020: **3,380** `view_item` events but only **4** `add_to_cart`, while **127** `begin_checkout` events still happened. Users reached checkout without any tracked cart adds.
- View→cart rate in Q01 is ~0 until 16 Nov, then jumps to 20%+ from 17 Nov.

**Recommendation**
- Treat every cart-based metric before ~16 Nov 2020 as invalid. Start cart analysis from 17 Nov, or flag the period on charts.
- In a real business, this is the kind of tracking gap that a weekly data-quality check (event counts by day) would catch.

---

## 7. Users keep going back to the basket

**Evidence (Q08)**

| Page | Views per user |
|---|---:|
| basket.html | **3.47** |
| store.html | 2.28 |
| Home (shop.) | 1.96 |
| Apparel | 1.63 |

- The home page is split across two domains: `shop.googlemerchandisestore.com/` (183,074 views) and `googlemerchandisestore.com/` (61,893). Combine them when reporting.

**Recommendation**
- Repeated basket visits suggest hesitation, such as unclear totals, shipping costs or delivery dates. Show the full cost and delivery estimate in the basket.
- Landing pages with the highest bounce rate: **[fill in: Q08 Part C]**.

---

## Supporting observations

- **Audience (Q05–Q07):** 57.9% of users are on desktop, 39.8% on mobile and 2.3% on tablet. The US is ~43% of users, and the top 5 countries are ~65%. *(Shares use the sum of device users as the denominator, an approximation.)* About 53% of users have `operating_system = 'Web'`, a placeholder, so OS analysis isn't reliable but browser analysis is.
- **Weekly pattern (Q01, 1–18 Nov):** weekend days average **2,332** sessions against **3,873** on weekdays, about 40% lower. Much of the traffic browses during the working week, so schedule promotions accordingly.
- **Season (Q01):** purchase rate rose from an average of **1.02%** (1–9 Nov) to **1.57%** (10–18 Nov) in the run-up to the holiday season.
- **New visitors (Q02):** on 1 Nov, 75% of session starts were first visits (1,946 of 2,594). Most traffic is new, so first impressions on landing pages matter.

## Figures to add after your run

| Metric | Query |
|---|---|
| Total revenue, transactions, AOV, average basket size for the full period | Q01 (sum the daily rows) or the `fact_order` table |
| Purchase rate by device and country | Q05 Part B, Q06 Part B |
| Bounce rate of the top landing pages | Q08 Part C |
| Median minutes from checkout to purchase | Q10 Part B |
| Share of repeated transaction IDs | Q01 QA, or `SUM(is_duplicate_transaction)` on `fact_order` |
