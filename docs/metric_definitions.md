# Metric definitions and data-quality notes

Where this project follows the brief, and where (and why) it adds to it.

## Keys

| Term | Definition |
|---|---|
| `session_key` | `user_pseudo_id + '-' + ga_session_id`. `ga_session_id` is only unique within one user, so it is never counted on its own. |
| User | Distinct `user_pseudo_id`. This identifies a browser or device, not a person: one shopper on a phone and a laptop counts as two users. |
| Transaction | Distinct `ecommerce.transaction_id`, excluding the placeholders `(not set)`, `(data deleted)` and `<Other>`. |

## Brief vs this project

| Q | Metric | Brief | This project | Why |
|---|---|---|---|---|
| Q01 | Sessions | Distinct session keys per event date | Same in the analysis query. `fact_session` dates a session by its first event | Avoids counting a midnight-crossing session on two days in the dashboard |
| Q01 | `revenue_per_user` | Revenue ÷ sessions | Kept as `revenue_per_session`; added a real `revenue_per_user` (revenue ÷ users) | The brief's name doesn't match its formula |
| Q01 | `ecommerce_purchases` vs transactions | Used interchangeably | `ecommerce_purchases` = purchase events; `transactions` = distinct valid IDs. AOV and basket use transactions | These differ when IDs repeat or are missing |
| Q03 | `session_source` | `traffic_source.source` | Same column, documented as the **first-user** source | GA4 export's `traffic_source` is user-scoped, not session-scoped |
| Q04 | `sessions` | Distinct users with `session_start` | Renamed `started_users`; added true `sessions` | The brief's column counts users |
| Q04 | First-time purchasers | `first_visit` events of users who purchased (correlated `EXISTS`) | Distinct users with `first_visit` who purchased, via a window function | Counts people, scans the table once |
| Q09 | Units / revenue hints | Swapped in the brief | Units = `SUM(quantity)`; revenue = `SUM(price × quantity)` on purchase events | Corrects the hints |
| Q10 | Funnel | Presence: session fired the event at all | Presence (main query) **plus** a strict in-order funnel using `>=` | Presence funnels can show a step larger than the one before it |

## Dashboard rule

Tables store **counts and 0/1 flags only**. Every rate is a Looker Studio calculated field, built as a ratio of sums, such as `SUM(session_purchase) / SUM(sessions)`. A rate stored per day and then averaged across days gives the wrong answer.

## Data-quality notes

1. **Add-to-cart gap.** `add_to_cart` is almost untracked before ~16 Nov 2020: 4 events on 1 Nov against 3,380 `view_item`. Cart-based rates before then are invalid.
2. **Obfuscated values.** Google anonymised the dataset. `<Other>`, `(data deleted)` and `operating_system = 'Web'` are placeholders, not real categories.
3. **First-user attribution only.** The 2020 export has no session-level source fields, so channel analysis credits the source that first acquired the user.
4. **Shipping step.** `add_shipping_info` fires almost exactly as often as `begin_checkout`, so it doesn't measure a separate user action.
5. **Timestamp ties.** Events from the same batch can share a timestamp. Ordered funnels use `>=` so these aren't dropped.
6. **Expected outputs in the brief contain errors.** For example, Q01's columns are misaligned for early November, and cart→purchase rates exceed 1. Numbers here are reconciled with QA queries rather than matched to the brief row by row.
