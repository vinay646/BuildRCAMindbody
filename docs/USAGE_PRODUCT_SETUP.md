# Usage products – setup checklist and the fix from the 12 Nov test

Learned from the QuantumBit Database test (order 00000104, account *Usage Test QuantumBit*): opportunity →
quote → order → activation → Transaction Journals → usage summaries.

## What was wrong and what fixed it

**Symptom:** journals stayed *Pending*, no usage summaries; Monitor → batch job → *Create Empty Summaries*
(flow `runtime_industries_usage__CreateEmptySummaries`) failed with
"The value "<UEA>::<usage resource>, …" for the UsageAccumulationPeriod parameter is invalid".
The entitlement account's billing period showed 1970-01-01.

**Cause:** the product had **no Product Usage Resource Policy**, so its usage resources had no aggregation
(accumulation) policy. Activation copies that gap to the asset's **Binding Object Usage Resource Policy**
records, and CreateEmptySummaries cannot find an accumulation period. It runs all entitlement accounts in
one batch, so one bad record fails every account in that run.

**Fix (in this order):**
1. On the product: one **Product Usage Resource Policy** per Product Usage Resource, with
   - Product Selling Model = the product's selling model (QB-DB: Term Annual)
   - Usage Aggregation Policy = a Usage Resource Billing Policy, e.g. *Monthly Total* (Sum, Monthly)
   - Rating Frequency Policy and Usage Overage Policy (we reused the ones on *Cloud Storage - 25gb*)
2. On assets already activated: fill Usage Aggregation, Rating Frequency and Usage Overage Policy on each
   **Binding Object Usage Resource Policy** that has them blank (one per asset × usage resource).
3. Monitor → the failed *Create Empty Summaries* batch job → **resubmit the failed records**.
4. Run **Create Usage Summary** (Data Processing Engine `Create_Usage_Summary_v4`): journals → *Processed*,
   Usage Summaries and Usage Ratable Summaries created for the billing period.

## Checklist for a new usage product

| # | Record | What to set |
|---|---|---|
| 1 | Unit of Measure Class + Unit of Measure | e.g. Texts, Transactions, USD |
| 2 | Usage Resource | Name, Code, Category = Usage, UoM class, default UoM, usage definition product, **Active** |
| 3 | Usage Resource Billing Policy (aggregation) | Accumulation Method (Sum / Peak), Period (Monthly), Active |
| 4 | Rating Frequency Policy, Usage Overage Policy | Reuse existing ones or create |
| 5 | Product | Usage Model Type (Anchor, Pack, Commit…), selling model option, **Active**, active price book entry |
| 6 | Product Usage Resource | Product ↔ Usage Resource, effective start date, Active |
| 7 | **Product Usage Resource Policy** | Per product usage resource: selling model + aggregation + rating frequency + overage policy. **Missing this is what broke the test** |
| 8 | Product Usage Grant | Included quantity per period, e.g. Ultimate 1,000 texts per location per month (optional) |
| 9 | Usage Product Grant Binding Policy | Binding Type = Self (grants bind to the product's own asset) |
| 10 | Rate Card + Rate Card Entries | Base / Tier rates per usage resource and UoM |
| 11 | Price Book Rate Card | Links the rate cards to the price book the quote uses |

**Order activation also needs:** billing and shipping address and a bill-to contact on the quote/order.

**Loading usage:** a **Transaction Journal** per usage record – Usage Type = UsageManagement, Status = Pending,
Reference Record = the asset, Usage Resource, Quantity + Quantity Unit of Measure, Activity / Start / End date.
Then run *Create Usage Summary*; next steps are *Create Liable Summary* (draw down the grant, overage) and
rating (billing period items).

**After activation, check:** the asset's Binding Object Usage Resource Policies have all three policies, and
the Usage Entitlement Account's billing period is not 1970.
