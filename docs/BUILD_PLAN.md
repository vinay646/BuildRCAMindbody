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
2. **Resolved Payer** = the account itself when Self-Pay, else the nearest Self-Pay ancestor.
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

## 5. What is drafted so far (Salesforce source, ready to move to the new repo)

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
