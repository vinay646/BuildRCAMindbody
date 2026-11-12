![Company logo](../logo.png)

# Mindbody on Salesforce ARM – Build Plan and User Stories

Source: *Mindbody on Salesforce ARM – Requirements Specification* (16 Oct 2026, 36 pages, 164 requirement IDs).
Target: a Salesforce org with Agentforce Revenue Management (Revenue Cloud Advanced) and ARM Billing enabled.

## 1. Is it feasible?

Yes. About 80% of the spec is standard ARM configuration plus some Apex and Flow. The remaining 20% needs
custom work or outside systems, and some of it can only be mocked in a demo org.

| Area | Feasible in ARM? | How | Risk |
|---|---|---|---|
| Account hierarchy, payer, addresses (2.3) | Yes | Custom fields, validation rules, Apex trigger | Low |
| Product catalog, bundles, selling models (CAT) | Yes, native | PCM: catalog, categories, Product2 bundles, PSM, attributes | Low |
| Price books, per-currency entries (PRC-01/02) | Yes | Needs **multi-currency** turned on (USD, GBP, AUD, EUR) | Low |
| Pricing waterfall, volume / term / frequency / promo / floor (12.2) | Yes | Pricing procedure + decision tables | **Medium** – hierarchy-wide location count (RLP-01) must reach the pricing context |
| Configuration rules CR-01..CR-18 | Mostly | CML constraint rules, qualification rules, validation rules | Medium – CML is new; CR-07, CR-17, CR-18 need extra Apex/Flow |
| Quoting, line groups per Ship-To, approvals (CFG) | Yes | Quote line groups, Advanced Approvals / Flow orchestration, doc gen | Medium |
| Orders, assets, amendments, renewals (LCM) | Yes, native | ARM Transaction Management | Medium – co-term and proration per location must be tested |
| Billing, invoices, dunning, credit memos (BIL) | Yes | ARM Billing | Medium – parent-pay invoice routing (RLP-03) is custom |
| Usage rating – payments, marketplace, SMS (BIL-06..10) | Yes | Usage Management, rate cards | **High** – 40,000 locations nightly (NFR-02); pooled SMS (RLP-05) |
| Rollups – ARR, AR, dunning flags (7A) | Yes, custom | Async Apex, reports / CRM Analytics | Medium |
| Integrations – NetSuite, provisioning, Stripe, tax, e-sign (INT) | Not inside Salesforce alone | MuleSoft or mock endpoints for the demo | **High** – needs the real systems |
| Migration with zero-variance reconciliation (7B) | Yes, as a project | Data loads + reconciliation object and reports | High – depends on legacy data |

**Open decisions before pricing and billing work** (spec section 9): real prices and volume bands, whether
payment fees are netted or invoiced, marketplace fee billing, renewal window and uplift, multiple billing
accounts per account. The demo build uses the spec's illustrative values.

## 2. Build order

The spec says to build the payer data model before the catalog (2.3), then follow section 10. Each phase ends
when its acceptance tests pass in a sandbox.

| # | Phase | Stories | Depends on | Start now? |
|---|---|---|---|---|
| 0 | Org setup: ARM + Billing licences, multi-currency (USD/GBP/AUD/EUR), permission sets, CLI / CI | – | – | **Yes** |
| 1 | Account hierarchy, payer model, addresses | US-01 – US-04 | 0 | **Yes** |
| 2 | Product catalog: categories, products, bundles, selling models, attributes | PD-01 – PD-09, PD-14 | 0 | **Yes** (in parallel with 1) |
| 3 | Price books and pricing procedure (waterfall, discounts, promos, floors) | US-09 – US-14 | 1, 2 | After 1 + 2 |
| 4 | Configuration rules CR-01 – CR-18 | PD-10 – PD-13 | 2 | After 2 |
| 5 | Quoting: line groups per Ship-To, approvals, quote document | US-15 – US-18 | 3, 4 | |
| 6 | Orders and assets: Draft vs Activated, routing by product type | US-19 – US-21 | 5 | |
| 7 | Billing: schedules, invoices, statements, usage rating, dunning | US-25 – US-28 | 6 | |
| 8 | Amendments, renewals, cancellations | US-22 – US-24 | 6, 7 | |
| 9 | Rollups and reporting (ARR, AR, re-parenting) | US-29 | 7 | |
| 10 | Integrations (mock first), migration | INT, US-30 | all | |

**Start with phases 0, 1 and 2.** They need no pricing decisions and everything else builds on them.

## 3. Phase 1 user stories – account hierarchy and payer model

### US-01 Account hierarchy up to four levels
*As a sales ops admin, I want accounts organised as corporate → region → franchisee → location, so that pricing,
billing and ARR can roll up through the brand.*

Acceptance criteria
1. Account has **Account Level** (Corporate, Region, Franchisee, Location) and **Root Account** (filled automatically).
2. Saving an account five levels deep is blocked with a clear message (also when a parent is moved).
3. Any account below Corporate without a parent is blocked.
4. Account carries ERP Id, Billing Id and Integration Status (New, Synced, Error).

Built: `Account_Level__c`, `Root_Account__c`, `ERP_Id__c`, `Billing_Id__c`, `Integration_Status__c`, validation rules
`US_01_ACC_DEPTH_*`, `AccountHierarchyService` + `AccountTrigger`.

### US-02 Self-pay and parent-pay
*As a billing manager, I want every account marked Self-Pay or Parent-Pay, so that charges invoice to the right payer.*

Acceptance criteria
1. **Payer Type** defaults to Self-Pay; a top account cannot be Parent-Pay.
2. **Resolved Payer** = blank when the account pays for itself (Self-Pay), else the nearest Self-Pay ancestor.
   (Salesforce does not allow an account lookup to point at its own record, so blank means "itself"; the same
   applies to Root Account on the top account.)
3. Changing a payer type or moving an account recalculates the payer for it and everything below it.
4. Pulse worked example (spec 7A) resolves to exactly three payers: Pulse Fitness Brands, Coastal Fitness LLC, Pulse Venice.

Built: `Payer_Type__c`, `Resolved_Payer__c`, validation rule `US_02_PAYER_Root_Must_Be_Self_Pay`, `AccountHierarchyService`.

### US-03 Address roles
*As a sales rep, I want a primary Bill-To and primary Ship-To per account, so that invoices and hardware go to the right place.*

Acceptance criteria
1. Addresses are Billing or Shipping, with one primary of each per account.
2. Every self-pay account has a primary Bill-To; every location has a primary Ship-To.
3. Addresses carry ERP Address Id and Integration Status.

Built: `ContactPointAddress.ERP_Address_Id__c`, `Integration_Status__c`; demo addresses from the loader.

### US-04 Demo accounts
*As the demo team, I want the four demo customers loaded, so that every pattern in the spec can be shown.*

Acceptance criteria: Sunrise Yoga (1 studio), Halo Spa Collective (HQ + 6 spas, HQ pays), Pulse Fitness Brands
(4 levels, 12 locations, mixed payers), Reformer Lab Pty (AUD, 4 studios) load with one command and can be reloaded
without duplicates.

Built: `MindbodyBuildLoader.run('accounts')`, data in static resource `MB_Build_Data`.

### RLP-01 Active location count (needed by pricing in phase 3)
*As the pricing engine, I need the number of active locations across the whole hierarchy on the top account.*

Acceptance criteria: count = active core-tier assets (Starter, Accelerate, Ultimate, Enterprise) under the root, by quantity;
recalculated asynchronously when assets change, and nightly.

Built: `Active_Location_Count__c`, `LocationCountService` (Queueable + Schedulable), `AssetTrigger`.

## 4. Phase 2 user stories – product catalog

| Story | As / I want | Acceptance criteria (summary) | Built by |
|---|---|---|---|
| PD-01 Catalog and categories | As product ops, one catalog with 7 categories and every SKU in one | Catalog *Mindbody Products*; Subscriptions, Add-ons, Messaging, Payments, Marketplace, Services, Hardware; 17 SKUs with Product Type | `catalog`, `products` steps |
| PD-02 Tier bundles | As a rep, Starter / Accelerate / Ultimate carry their included features at $0 | Tier matrix 3.1 as required components; Ultimate has SMS Allowance 1,000 | `bundles`, `attributes` |
| PD-03 Enterprise | As a field rep, Enterprise is a configurable bundle priced per deal | No list price; Term 24/36 only | `products`, `bundles` |
| PD-04 Add-ons | As a rep, AI Concierge and Branded app are offered only where allowed | Optional on Accelerate; Branded app only on Ultimate; never AI Concierge add-on on Ultimate | `bundles` (rules in phase 4) |
| PD-05 Usage products | Payments, Marketplace fee, SMS overage have no quote price | $0 entries only; rate cards in phase 7 | `products`, `pricebooks` |
| PD-06 One-time products | Services and hardware use only the One-Time selling model | One-Time PSM; hardware gets ERP item ID from the integration | `products` |
| PD-07 Attributes | Vertical, Region, Location Count, Prior System, Payments Opted In, Card Present, SMS Allowance, Branded App Platform | Picklist values per spec 12.6 | `attributes` |
| PD-09 Selling models and frequencies | Recurring products offer the right terms and billing frequencies | 3 selling models: Evergreen Monthly, Term Monthly, One-Time (ARM allows one per type + pricing term). Contract length is the quote line's term, limited by **Allowed Term Months** (Starter/Accelerate/Ultimate 12/24/36, Enterprise 24/36, TAM 12). Starter billing Monthly/Annual only. Entry per currency × selling model | `catalog`, `products`, `pricebooks` |
| PD-14 Integration status | Every product shows its ERP sync status | New on create; owned by the integration afterwards | `products` |

## 5. Phase 3 – pricing (standard features only)

Rule for the whole build: **standard ARM / Salesforce features first; anything custom is listed below with the
reason.** The pricing waterfall (spec 12.2) is built only from standard pieces – see
[PHASE3B_PRICING_PROCEDURE.md](PHASE3B_PRICING_PROCEDURE.md):
volume, term and billing-frequency discounts are standard Price Adjustment Schedules (types Volume and Term)
with tiers; promotions are standard Promotions with coupon codes; the floor is a standard price book; the
waterfall shows in ARM's standard price breakdown. Seed data: loader step `pricingschedules`.

### Custom pieces that remain, and why

| Custom | Reason no standard feature fits |
|---|---|
| Account: Payer Type, Resolved Payer, Root Account + `AccountHierarchyService` | No standard self-pay / parent-pay or top-of-hierarchy field; billing rollup depends on them (2.3, RLP-03) |
| Account: Active Location Count + `LocationCountService` | No standard rollup across a 4-level account hierarchy (RLP-01) |
| Account: Account Level, Segment | No standard field for corporate / region / franchisee / location, or SMB / mid-market / enterprise |
| ERP Id, Billing Id, Integration Status (account, product, address) | Spec needs ERP IDs and sync status on every record (NFR-07) |
| Product: Allowed Billing Frequencies, Allowed Term Months | No standard allowed-frequency / allowed-term list per product (CAT-07, CR-13) |
| Quote: Hierarchy Location Count | The pricing procedure needs the hierarchy count; no standard field holds it |
| Contract: Master Contract | Standard contracts have no parent-contract link (RLP-07) |
| `MindbodyBuildLoader` | Loads the demo data; not part of the runtime |

Switched to standard: Product Type → **Product Family**; Vertical → **Industry**; Unit Of Sale → **Quantity Unit
of Measure**; Core Tier flag → **classification** *Mindbody Subscription Tier*; discount tables and the pricing
Apex → **Price Adjustment Schedules / Promotions / floor price book**; custom quote line discount fields →
**standard price waterfall**. The `cleanup` action deletes the replaced custom pieces from the org.

## Phase 4 – product and configuration rules (in progress)

| Rule | Standard feature | Status |
|---|---|---|
| CR-13 billing frequency and contract term allowed per product | Validation rules on Quote Line (`CR_13_Billing_Frequency_Allowed`, `CR_13_Contract_Term_Allowed`) | ✅ deployed |
| CR-04, CR-05, CR-08 in Browse Products | **Bundle-only add-ons**: AI Concierge add-on, Branded app and Branded app setup are not in a catalog category (sell only with other products) – they are added only inside the tier bundles, whose structure allows them only where valid. CML "disable" rules were tried first: Browse Products does not apply them in this release | ✅ Tested 12 Nov: gone from the catalog, bundle add-ons work |
| CR-04, CR-05, CR-07, CR-09 (cart-level: Starter add-ons, AI Concierge on Ultimate, one Branded app, hardware needs Payments) | **Constraint model** *Mindbody Plans* (`cml/MindbodyPlans.cml`, generated by `scripts/build_cml.py`; product links by loader step `constraints`) | ✅ Active – CR-05 tested 12 Nov (message on the quote); CR-09 enforced: `require` auto-adds Mindbody Payments when hardware is added (tested 12 Nov); CR-04/CR-05 also blocked in the catalog by bundle-only add-ons |
| CR-05 AI Concierge add-on blocked on Ultimate (also outside the bundle) | **Product Configuration Rule** *CR 05 AI Concierge included in Ultimate* – scope Transaction, Validate / Error (definition in `reference/config-rules/CR-05.json`) | ✅ built in the builder, Active |
| CR-01 – CR-07, CR-09, CR-18 (tier per location, included features, add-on eligibility, quantities, hardware needs Payments, downgrade guard) | **Product Configuration Rules** (built in Setup → Product Configuration Rules) | Builder works (library fixed 11 Nov) – rules built in the builder, see below |
| CR-08 Branded app setup added once per brand | **Bundle**: Branded app (MB-APP) is a bundle with Branded app setup (MB-APP-SET, $1,500 one-time) as a required child, quantity 1 constant, priced separately – no rule needed | Loader step `bundles` |
| CR-15 region availability (Capital, Insurance, hardware) | **Product qualification rule** (standard) by **Account › Region** (`MB_Region__c`: NA, UK, AU, EU; the accounts step sets it from the country). Product discovery context attribute `MB_Region__c` (tag `MbRegion`) → `RLM_ProductQualification` decision table input 4 `MB_Region__c` → one `ProductQualification` per hardware product and allowed region (NA, UK, AU – data `productQualifications`, loader step `qualification`). Hardware is hidden in Browse Products for EU accounts; blank Region shows it. The qualification procedure passes `MB_Region` ← context tag `MbRegion` to Evaluate Qualification (deployed; procedure parameter names cannot contain `__c`, and the Product Qualification Region is Text because the decision table reads strings). Old validation rule and country formula removed; the context keeps an unused `MB_Hardware_Region__c` attribute (attributes cannot be deleted by deploy). Capital and Insurance not in the catalog yet | Done – tested (EU hidden, NA/AU shown) |
| CR-10 promo conditions, CR-11/12 recommendations | Promotions qualifiers / product recommendations | To do |
| **Design (13 Nov):** one opportunity and quote per account – every account, location included, can buy; billing and invoices follow the account's Payer Type (Self-Pay bills itself, Parent-Pay bills the resolved payer). No quote line groups per location, so the per-location rules are per-quote rules | – | Decided with the product owner |
| CR-01 one tier per location, CFG-13 no duplicate product per Ship-To, CR-07 one Branded app | **Constraint model** hard `constraint`s on the virtual Quote: one plan (Starter/Accelerate/Ultimate/Enterprise) per quote; Mindbody Payments, TAM, Marketplace fee, SMS once per quote (add-ons are bundle-only, hardware/services may repeat); one Branded app. Across a brand's quotes (existing assets): phase 6 | CML generated – paste as a new model version, then loader `constraints` (3 new product types) |
| CR-14 region vs price book | Validation rule `CR_14_Region_Price_Book` (Quote): currency and regional price book must match Account › Region (NA USD, UK GBP, AU AUD, EU EUR); skipped when Region is blank | ✅ deployed |
| CR-16 Enterprise needs master contract | Validation rule `CR_16_Enterprise_Master_Contract` (Quote Line): MB-ENT only when Account › Master Contract (new lookup) on the quote's account or its top account is Activated | ✅ deployed |
| CR-17 payer override | Quote › Payer Override (lookup, Self-Pay accounts only) + Payer Override Reason; validation rule `CR_17_Payer_Override_Reason`. Approval with the approval matrix (phase 5b) | ✅ deployed (approval in 5b) |

**Configuration rule builder – findings (11 Nov 2026, `probe-config-rule`):**
- Product Configuration Rules can't be created by API (`ProductConfigurationRule` isn't createable), so they're
  built in the Setup builder, which stores them in a Business Rules Engine *rule library* with usage type
  `Configurator`.
- The org had only the DRO rule library (usage type `Dfo`, used by order fulfilment). No Configurator library
  existed, so the builder fails with "Cannot read properties of undefined (reading 'RuleLibraryVersions')".
- `ruleLibraryDefinitions/Mindbody_Product_Rules` (usage type Configurator, standard metadata) was deployed.
  Salesforce created the definition record but no definition version and no library, and a retrieve returns it
  with empty fields. A library or version can't be added by API without a definition version.
- **Resolved:** Revenue Settings → *Set Up Configuration Rules with Business Rules Engine* off, save, on, save
  created the standard library *Configurator Rule* (usage type Configurator, context RLM_SalesTransactionContext,
  version 1 Active). Only one Configurator library is allowed, so the hand-deployed `Mindbody_Product_Rules`
  definition is removed (`cleanup-rule-library` action).



From the `inventory` step (the org is Salesforce's QuantumBit demo org: 314 products, 5 catalogs).

| Org record | Used for |
|---|---|
| Selling models *Evergreen Monthly*, *Term Monthly*, *One-Time* | All Mindbody products (PD-09). Contract length 12/24/36 is the quote line term, limited by *Allowed Term Months* |
| *Default Proration Policy* | Selling model options (BIL-04) |
| *Bundle to Bundle Component Relationship* | Tier bundle components (PD-02) |
| *Billing Policy – Advance* / *– Arrears* | Phase 7: subscriptions in advance, usage in arrears (BIL-01) |
| Billing treatments and legal entities US, Canada, EU, UK | Phase 7 (BIL-13, spec 2.3). **AU legal entity and billing treatment must be added** for Reformer Lab Pty (AUD) |
| Rate card types Base / Tier, usage resources | Phase 7: Mindbody usage resources (payments, marketplace, SMS) are added; rate card types reused |

Not reused: QuantumBit catalogs, classifications and attributes (no overlap with Mindbody's names).

## 7. What is drafted so far (Salesforce source, ready to move to the new repo)

```
sfdx-project.json
force-app/main/default/
  objects/Account/fields/…            11 fields (level, payer, root, resolved payer, location count, ERP ids, …)
  objects/Account/validationRules/…   3 rules (US-01 depth, US-01 parent required, US-02 root self-pay)
  objects/Product2/fields/…           Product Type, Allowed Billing Frequencies, ERP Item Id, Integration Status, Unit Of Sale
  objects/Product2/validationRules/…  CAT-06 product type required, CAT-10 frequencies only on recurring
  objects/ContactPointAddress/fields/ ERP Address Id, Integration Status
  objects/*__mdt + customMetadata/    Volume bands, term, frequency, tier floor/auto-approve, promotions (spec 12.2)
  classes/AccountHierarchyService     root + resolved payer, depth guard on re-parent
  classes/LocationCountService        RLP-01 location count (async)
  classes/MindbodyBuildLoader         loads catalog, products, bundles, attributes, price books, demo accounts
  triggers/AccountTrigger, AssetTrigger
  staticresources/MB_Build_Data.json  all catalog, price and demo account data in one editable file
```

Deploy and load, step by step:

```bash
sf project deploy start --target-org <alias>
sf apex run --target-org <alias> <<< "MindbodyBuildLoader.run('accounts');"
sf apex run --target-org <alias> <<< "MindbodyBuildLoader.run('catalog');"
sf apex run --target-org <alias> <<< "MindbodyBuildLoader.run('products');"
sf apex run --target-org <alias> <<< "MindbodyBuildLoader.run('bundles');"
sf apex run --target-org <alias> <<< "MindbodyBuildLoader.run('attributes');"
sf apex run --target-org <alias> <<< "MindbodyBuildLoader.run('pricebooks');"
```

Not yet done: Apex test classes, permission set (field access), page layouts, and a first deploy to a real org –
this session could not reach Salesforce, so nothing has been deployed or compiled yet. ARM object field names
(ProductSellingModel, ProrationPolicy, AttributeDefinition, …) vary by release; the loader skips unknown fields
with a warning instead of failing, and the first sandbox run will show what to adjust.
