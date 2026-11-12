![Company logo](../logo.png)

# Phase 3b – Mindbody pricing with standard ARM features only

The spec 12.2 waterfall built from out-of-the-box Agentforce Revenue Management pieces. Everything below was
checked against what ExploremoreRCA actually has (`explore` action, 11 Nov 2026): the standard pricing procedure
*RLM Revenue Management Default Pricing Procedure*, its decision tables, the *RLM_SalesTransactionContext*, and the
pricing objects' fields and picklist values.

## Design – which standard feature does each step

| Spec step | Standard feature | Records (loader step `pricingschedules`) |
|---|---|---|
| 1 List price | Price book entry – *Get base prices from price book* step | regional price books (step `pricebooks`) |
| 2 Contract price (RLP-07) | Contract Item Price – *Contract Pricing Entries* step | per master agreement (phase 6) |
| 3 Volume by hierarchy locations (PRC-04, RLP-01) | **Price Adjustment Schedule, type Volume** + Volume Discount step | *Mindbody Hierarchy Volume*: 1–3 0%, 4–10 5%, 11–50 10%, 51–200 15%, 201+ 20% |
| 4 Term (PRC-06) | **Price Adjustment Schedule, type Term** + Volume Discount step | *Mindbody Contract Term*: 0–23 0%, 24–35 5%, 36+ 10% |
| 5 Billing frequency (PRC-06) | **Price Adjustment Schedule, type Volume** (quantity = months per billing period; ARM tiers do not accept type Custom) + Volume Discount step | *Mindbody Billing Frequency* (months per period): 1–2 0%, 3–5 2%, 6–11 4%, 12+ 8% |
| 6 Promotion (PRC-07) | **Promotions** (Promotion, Promotion Target, Coupon) | LAUNCH3 ($39 fixed price, Starter), SWITCH50 (50%, Accelerate/Ultimate), GROW2 (100%, any tier) |
| 7 Manual discount | Manual Discount step | – |
| 8 Floor (PRC-18) | **Price book** *Mindbody Floor Prices* read by a second price-book step | Starter 59, Accelerate 189, Ultimate 339 (USD; GBP/AUD/EUR converted) |
| Approvals (CFG-16) | Standard approval rules (phase 5) | auto-approve 10 / 20 / 25%, Enterprise deal desk |

Tiers are created for each product × selling model × currency, because the standard *Price Adjustment Tier*
decision table matches on schedule, product, selling model, currency, effective dates and quantity bounds.

**One custom input remains:** *Quote → Hierarchy Location Count* (formula from the root account's Active Location
Count). Reason: no standard field counts locations across a 4-level account hierarchy, and the volume band
needs it (RLP-01).

## Before you start (GitHub Actions → Salesforce build)

1. `deploy` – standard picklist values (Product Family, Industry, Unit of Measure) and the updated loader.
2. `load` → `products` – Product Family, Unit of Measure, Semi-Annual frequency.
3. `load` → `accounts` – demo customers (Industry = vertical).
4. `load` → `pricingschedules` – 3 schedules + tiers, floor price book, 3 promotions with coupons.
5. `cleanup` – deletes the custom pieces these replace (custom pricing table, discount metadata, custom quote
   line discount fields, Product Type / Unit Of Sale / Core Tier / Vertical fields, the pricing Apex). Run it
   only after steps 1–4 succeeded.

## Billing by legal entity (12 Nov 2026, tested end to end)

| Level | Field | Set by |
|---|---|---|
| Account | `MB_Legal_Entity__c` (lookup to Legal Entity) | flow `MB_Account_Legal_Entity` from Region: NA = US, UK, EU, AU (loader fills existing accounts) |
| Opportunity | `MB_Legal_Entity__c` (formula, read-only) | Account |
| Quote | standard Legal Entity | flow `MB_Quote_Legal_Entity` on create |
| Quote Line | standard Legal Entity + Billing Treatment | flow `MB_Quote_Line_Billing_Treatment`: quote's legal entity, then the active treatment of the product's billing policy for that legal entity |

Loader step `billing`: AU legal entity; **Mindbody Billing Policy - Advance** (subscriptions, one-time; Can Change
Billing Frequency on) and **- Arrears** (usage: MB-PAY, MB-SMS, MB-MKT), both selecting by legal entity, one treatment
per legal entity (US/UK/EU/AU); the earlier default-selection policy is Inactive. Why a flow: the standard quote line
editor does not fill the billing treatment, and a line billed at another frequency than its selling model (Term
Monthly → Annual) is rejected without one.

Test (`usage-summary`, path `legal-flow-test`), Pulse quote 00000033, nothing given but products: legal entity US on
quote and lines; Ultimate Annual → Mindbody - US - Advance, **$371.85**; SMS overage → Mindbody - US - Arrears.

## Status (12 Nov 2026, evening) – version 3 active, Annual tested

- **Version 3** (`RLM_DefaultPricingProcedure_RLM_Revenue_Management_Default_Pricing_Procedure_V30`) is the only active
  version; versions 1 and 2 are inactive. It reads only values present before a line is saved: billing months from the
  standard `ItemBillingFrequency` (four standard ListGroup + filter + Assignment groups), the volume bound from the quote's
  Hierarchy Location Count, the term bound from the quote's Term (Months). Built by `scripts/build_pricing_v3.py`;
  deployed from `deploy/pricing-v3` (active versions cannot be redeployed). New versions must first be created in the
  builder (Save As New Version) – a deploy cannot create one ("LatestVersionSnapshotId not found").
- **Billing:** loader step `billing` – Mindbody Billing Policy (Default selection) → Mindbody Billing Treatment – Advance
  (Can Change Billing Frequency = on) on every MB- product. A quote line whose frequency differs from the selling model
  (Term Monthly → Annual) needs that treatment on the line.
- **Test P02 via Place Sales Transaction (new line, Annual):** $499 → $449.10 → $404.19 → **$371.85**; line total
  $26,773.55 (quote 00000029). Run: `usage-summary`, path `pricing-place`.

## Status (12 Nov 2026, tested)

- **One procedure:** the Mindbody steps are version 2 of `RLM_DefaultPricingProcedure`; `MB_Pricing_Procedure` is deleted.
  Quotes are priced through the standard procedure plan `RLM_Quote_Pricing_Procedure_Plan` (section 1 = this procedure).
- **Tiers:** one USD tier set serves every currency (the standard Volume Discount step does not pass the currency to the
  tier lookup; four currency copies made it fail with "Duplicate entries found while looking up VolumeDiscount").
- **Subscription Term** must be filled on term lines – the contract term step reads it, and a blank value matches every
  term tier (same duplicate error). The quote line date flows set it from the quote's Term (Months).
- **Test P02** (Pulse Fitness Brands, 12 active locations, Ultimate x2, 36 months, Monthly): $499 → $449.10 (volume 10%)
  → $404.19 (term 10%) → $404.19 (Monthly 0%); line total $29,101.68. Run: `usage-summary`, path `pricing-test`.
- **Open:** Quarterly/Semi-Annual/Annual lines are refused with "Add a Billing Treatment …" – the Mindbody products need a
  standard billing policy and billing treatment before the billing frequency discount can apply.

## Status (13 Nov 2026)

**Unblocked:** Salesforce Support fixed the release issue behind "Ensure that the lookup table in the ListPrice step
is valid". The org's default procedure now carries their fix (lookup parameter order, `usageSubtype`), so it is kept
exactly as they left it and an active version cannot be updated by deploy anyway. The Mindbody steps are deployed as a
**separate procedure, `MB_Pricing_Procedure` (Mindbody Pricing Procedure)**, built by `scripts/build_pricing_procedure.py`
from the default in `reference/`. Next: Setup → Salesforce Pricing Setup → make it the default, Sync Pricing Data, test P02.

## Status (11 Nov 2026)

**Blocked by the org:** no pricing procedure can be saved in ExploremoreRCA – Setup Clone, builder Save and Metadata
API deploy all fail with "Ensure that the lookup table in the ListPrice step is valid" (details and reproduction:
[SUPPORT_CASE_PRICING_PROCEDURE.md](SUPPORT_CASE_PRICING_PROCEDURE.md)). Everything else for phase 3 is in the org:
schedules and tiers, floor price book, promotions and coupons, quote line inputs, context attributes. The procedure
change below is ready in `force-app` and deploys once Salesforce fixes the lookup validation.

## Steps 1–4 – built as metadata (no Setup clicks)

`scripts/build_pricing_procedure.py` builds both pieces from the org's own files (`reference/`, retrieved at the
org's API version 68.0) and they deploy with the rest of `force-app`:

| Metadata | What changed |
|---|---|
| `expressionSetDefinition/RLM_DefaultPricingProcedure` | The org's default procedure, **updated in place**. Its standard Volume Discount step now uses schedule **Mindbody Hierarchy Volume** with tier bounds = `MbVolumeLocationCount`; two copies of that standard step follow it: **Mindbody Contract Term** (bounds = standard `ItemSubscriptionTerm`) and **Mindbody Billing Frequency** (bounds = `MbBillingPeriodMonths`). All other steps unchanged. |
| `contextDefinitions/RLM_SalesTransactionContext` | Two line attributes, `MbVolumeLocationCount` and `MbBillingPeriodMonths`, hydrated from quote line fields – added the same way as the org's own `RLM_Distributor_Unit_Price__c` |
| Quote line `Volume_Location_Count__c` (formula) | Quote's Hierarchy Location Count + the line's quantity. Custom because no standard field holds the hierarchy count |
| Quote line `Billing_Period_Months__c` (formula) | Monthly 1, Quarterly 3, Semi-Annual 6, Annual 12. Custom because tiers need a number and Billing Frequency is text |

**Why the default procedure is updated instead of a separate Mindbody procedure:** in ExploremoreRCA, creating a
*new* pricing procedure fails – by deploy and by Setup → Clone alike, also after *Sync Pricing Data* – with
"Ensure that the lookup table in the ListPrice step is valid", while an update of the existing procedure deploys.
Other products are not affected: the term and frequency tiers exist only for Mindbody products, and the volume step
previously pointed at the standard *Price Adjustment Tier* schedule, which was inactive with no tiers.
After a Salesforce upgrade of the default procedure: `explore-context` → replace `reference/` → re-run the script.

Schedule Ids come from the `ids` action: `python3 scripts/build_pricing_procedure.py VOLUME_ID TERM_ID FREQUENCY_ID`.

Known limit: the volume count adds **this line's** quantity, not the sum of all core-tier lines on the quote.

**After every pricing data load** (`pricebooks`, `pricingschedules`): Setup → Salesforce Pricing Setup → **Sync
Pricing Data**, so quotes see the new prices and tiers.

## Step 5 – Promotions

Setup → **Revenue Settings** (or *Salesforce Pricing Setup*) → turn on **Promotions** for quotes if it is off.
The loader created LAUNCH3, SWITCH50 and GROW2 with their targets and coupon codes; a rep applies a coupon on the
quote and the promotion shows as a *Promotion* adjustment on the line.

Not standard and handled elsewhere:
- **Promo conditions** (Payments opted in, competitor, term minimum – CR-10) → product rule in phase 4.
- **Promo length** (months 1–3, 1–6, 2) → the promo price applies to the first ramp segment; the step-up to the
  standard price is the ramp schedule (PRC-09, LCM-15) in phase 5.

## Step 6 – Floor price

Duplicate the standard *Get base prices from price book* step after Manual Discount: price book = **Mindbody Floor
Prices**, output `UnitPrice` → variable `FloorPrice`. Phase 5's approval rule compares the net unit price with
`FloorPrice` (below floor → VP Sales then Finance).

## Step 7 – Activate and check

Activate the procedure; Revenue Settings → default pricing procedure = **Mindbody Recurring Pricing Procedure**.

Check (spec 12.2 worked example): Pulse quote, USD price book, 2 × Ultimate, Subscription Term 36, Billing
Frequency Annual, with 12 active Pulse locations → 499.00 → 449.10 (volume 10%) → 404.19 (term 10%) → 371.85
(frequency 8%). Until Pulse has active assets (phase 6) Hierarchy Location Count is 0; quoting 14 Ultimate
locations on the line gives the same volume band.

## Step 8 – Save it in the repo

Run `retrieve`; Claude adds the procedure and context definition to `force-app`.
