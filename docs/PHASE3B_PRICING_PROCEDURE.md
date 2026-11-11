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
| 5 Billing frequency (PRC-06) | **Price Adjustment Schedule, type Custom** + Volume Discount step | *Mindbody Billing Frequency* (months per period): 1–2 0%, 3–5 2%, 6–11 4%, 12+ 8% |
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

## Step 1 – Context: expose the hierarchy count

Setup → **Context Definitions** → *RLM_SalesTransactionContext* → **Extend** → API name
`Mindbody_Sales_Transaction_Context`. On the **SalesTransaction** node add attribute `HierarchyLocationCount`
(Number) mapped to **Quote.Hierarchy_Location_Count__c**. `SubscriptionTerm` and `BillingFrequency` are already in
the standard context. Activate.

## Step 2 – Clone the standard procedure

Setup → **Pricing Procedures** → *RLM Revenue Management Default Pricing Procedure* → **Save As** →
`Mindbody Recurring Pricing Procedure` (`Mindbody_Recurring_Pricing_Procedure`), context
*Mindbody_Sales_Transaction_Context*.

## Step 3 – Point the volume step at the hierarchy

The standard step *Calculate net unit price and net total price after volume-based discount* uses
`PriceAdjustmentScheduleId = VolumePASIdConstant` and `Quantity = LineItemQuantity`.

1. Add a **Grouping and Aggregate** step (same type as the standard *Calculate subtotal…* steps): sum
   `LineItemQuantity` of lines whose product is based on classification *Mindbody Subscription Tier* →
   variable `NewLocations`.
2. Add an **Assignment** step: `VolumeLocations = HierarchyLocationCount + NewLocations`.
3. On the volume step: set the constant `VolumePASIdConstant` to the Id of **Mindbody Hierarchy Volume**, and its
   **Quantity** input to `VolumeLocations`.

## Step 4 – Term and frequency: two more volume steps

Duplicate the volume step twice, right after it:

| Copy | PriceAdjustmentScheduleId (new constant) | Quantity input |
|---|---|---|
| Term discount | Id of **Mindbody Contract Term** | `SubscriptionTerm` (blank → 0) |
| Frequency discount | Id of **Mindbody Billing Frequency** | `FrequencyMonths` – Assignment before it: Monthly → 1, Quarterly → 3, Semi-Annual → 6, Annual → 12 |

Each copy keeps `InputUnitPrice = NetUnitPrice`, so the discounts compound in spec order and each appears as its
own line in the standard price waterfall.

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
