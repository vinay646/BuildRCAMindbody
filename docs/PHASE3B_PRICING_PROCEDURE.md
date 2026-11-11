![Company logo](../logo.png)

# Phase 3b – Mindbody pricing procedure (native ARM)

Builds the spec 12.2 waterfall into ARM's own pricing engine so every quote line shows
List → Contract → Volume → Term → Frequency → Promo → Manual → Net, and the floor check.

The rules already exist and are tested: `MindbodyPricing` + `MindbodyPricingTest` (10/10 passing in ExploremoreRCA).
This guide wires the same numbers into a pricing procedure. Use `MindbodyPricingTest`'s numbers to check each step.

> Screen labels below are from Agentforce Revenue Management; they can differ slightly by release.
> Keep the **API names exactly as written** – the `retrieve` action looks for them.

## Before you start (GitHub Actions → Salesforce build)

1. `deploy` – adds the **MB Pricing Rule** object and the **Core Tier** product flag.
2. `load` → `products` – sets Core Tier on Starter, Accelerate, Ultimate, Enterprise.
3. `load` → `pricingtables` – fills MB Pricing Rule from the custom metadata (5 volume, 4 term, 4 frequency,
   7 promotion, 4 floor rows). Check in the org: App Launcher → **MB Pricing Rules** (or a report on it).
4. `load` → `accounts` – demo customers, so you can test on a real quote.

## Step 1 – Extend the sales transaction context

The procedure can only read fields that are in its context definition.

1. Setup → **Context Definitions** → **RLM_SalesTransactionContext** → **Extend** (or Clone if Extend is not offered).
   - Name: `Mindbody Sales Transaction Context`, API name `Mindbody_Sales_Transaction_Context`.
2. On the **SalesTransaction** (header) node, add attributes and map them to the **Quote**:

   | Attribute | Type | Quote field |
   |---|---|---|
   | `HierarchyLocationCount` | Number | `Hierarchy_Location_Count__c` |
   | `PromoCode` | Text | `Promo_Code__c` |

3. On the **SalesTransactionItem** (line) node, add attributes and map them to **QuoteLineItem**
   (inputs come from the product / line, outputs are written back):

   | Attribute | Type | Direction | QuoteLineItem field |
   |---|---|---|---|
   | `IsCoreTier` | Boolean | input | `Product2.Is_Core_Tier__c` |
   | `ProductCode` | Text | input | `Product2.ProductCode` (often already in the context) |
   | `TermMonths` | Number | input | the line's subscription term (`SubscriptionTerm` – confirm the name on your line) |
   | `BillingFrequency` | Text | input | `BillingFrequency` (often already in the context) |
   | `VolumeDiscount` | Number | output | `Volume_Discount__c` |
   | `TermDiscount` | Number | output | `Term_Discount__c` |
   | `FrequencyDiscount` | Number | output | `Frequency_Discount__c` |
   | `PromoDiscount` | Number | output | `Promo_Discount__c` |
   | `PromoPrice` | Currency | output | `Promo_Price__c` |
   | `FloorPrice` | Currency | output | `Floor_Price__c` |
   | `BelowFloor` | Boolean | output | `Below_Floor__c` |
   | `CombinedDiscount` | Number | output | `Combined_Discount_Percent__c` |
   | `MbNetPrice` | Currency | output | `Net_Price__c` |

4. Save and **Activate** the context definition.

## Step 2 – Decision tables over MB Pricing Rule

Setup → **Decision Tables** → New. For each table: Source object **MB Pricing Rule** (`MB_Pricing_Rule__c`),
filter `Is_Active__c = true` **and** the Rule Type shown, then **Activate**.

| API name | Filter: Rule Type | Input columns (operator) | Output columns |
|---|---|---|---|
| `MB_Volume_Discount` | Volume | `Min_Value__c` (less or equal to the count), `Max_Value__c` (greater or equal to the count) | `Discount_Percent__c` |
| `MB_Term_Discount` | Term | `Min_Value__c` (equals term months) | `Discount_Percent__c` |
| `MB_Frequency_Discount` | Frequency | `Frequency__c` (equals) | `Discount_Percent__c` |
| `MB_Promotion` | Promotion | `Promo_Code__c` (equals), `Product_Code__c` (equals) | `Discount_Percent__c`, `Promo_Price__c`, `Promo_Months__c`, `Min_Term_Months__c` |
| `MB_Tier_Floor` | Floor | `Product_Code__c` (equals) | `Floor_Price__c`, `Auto_Approve_Percent__c` |

Term rows exist for 0 (evergreen), 12, 24 and 36 months. If your line stores the term in another unit, convert
it to months in Step 3 before the lookup.

## Step 3 – Clone the default procedure and add the Mindbody steps

1. Setup → **Pricing Procedures** → **RLM Revenue Management Default Pricing Procedure** → **Save As / Clone**.
   - Name `Mindbody Recurring Pricing Procedure`, API name `Mindbody_Recurring_Pricing_Procedure`.
   - Context definition: **Mindbody_Sales_Transaction_Context**.
2. Keep the default elements for **List Price** (price book entry) and **Contract Pricing** (contract item price –
   RLP-07). When a contract price is found, skip the next three discounts (add a condition on the contract-price
   output, or put the three steps in a branch that runs only when there is no contract price).
3. **New locations on the quote** – add an aggregate / rollup element: sum `Quantity` of lines where
   `IsCoreTier = true`, into a variable `NewLocations`. Then a formula / assignment:
   `VolumeCount = HierarchyLocationCount + NewLocations`.
4. **Volume (step 3)** – Lookup element on `MB_Volume_Discount` with `VolumeCount` → `VolumeDiscount`; then a
   percentage discount / price adjustment element applying `VolumeDiscount` %. Apply to core tiers and add-ons
   (not to one-time products).
5. **Term (step 4)** – Lookup `MB_Term_Discount` with `TermMonths` (blank → 0) → `TermDiscount`; percentage discount.
6. **Frequency (step 5)** – Lookup `MB_Frequency_Discount` with `BillingFrequency` → `FrequencyDiscount`; percentage discount.
7. **Promotion (step 6)** – only when `PromoCode` is filled: Lookup `MB_Promotion` with `PromoCode` + `ProductCode`.
   Write `PromoPrice` (fixed-price promos) or `PromoDiscount` (percentage promos) to the line. The standard
   price is **not** reduced – the promo is time-boxed (PRC-07) and the floor check uses the standard price.
   Promo conditions (Payments opted in, competitor, term minimum – CR-10) are enforced as a rule in phase 4.
8. Keep the default **Manual Discount** element (step 7).
9. **Floor check (step 8)** – Lookup `MB_Tier_Floor` with `ProductCode` → `FloorPrice`, `AutoApprove`;
   assignments: `MbNetPrice = net unit price`, `BelowFloor = MbNetPrice < FloorPrice`,
   `CombinedDiscount = (ListPrice − MbNetPrice) / ListPrice × 100`.
10. Save, **Activate**.
11. Setup → **Revenue Settings** (or Salesforce Pricing Setup) → set **Mindbody Recurring Pricing Procedure** as the
    default pricing procedure for quotes and orders.

## Step 4 – Check against the spec worked example

Create an opportunity on **Pulse Fitness Brands** → quote in **North America & Asia (USD)** → 2 × **Ultimate**,
36-month term, billing frequency **Annual**. With 12 active Pulse locations the line must show:

| Step | Expected |
|---|---|
| List | 499.00 |
| Volume (14 locations) | 10% → 449.10 |
| Term (36) | 10% → 404.19 |
| Frequency (Annual) | 8% → 371.85 |
| Combined | 25.48% (spec: 25.5%) – above Ultimate's 25% auto-approve → sales manager approval (phase 5) |
| Below Floor | false (floor 339) |

Until the Pulse locations have active assets (phase 6), Hierarchy Location Count is 0: the same quote then prices
with the 1–3 band (0%) – that is expected. To test the band now, quote 14 Ultimate locations on one line
(NewLocations = 14 → 10%).

## Step 5 – Save the procedure in the repo

GitHub Actions → Salesforce build → `retrieve`. It pulls the procedure, the five decision tables and the context
definition (`manifest/pricing-procedure.xml`) and attaches them to the run as **retrieved-pricing-procedure**.
Tell Claude the run is done – it adds the files to `force-app` so the procedure is version-controlled and can be
deployed to the next org.
