![Company logo](../logo.png)

# Salesforce Support case – pricing procedures cannot be saved

**Org:** ExploremoreRCA (Developer Edition, org ID 00Dhm000005qrRxEAI, API 68.0)
**Product:** Agentforce Revenue Management – Salesforce Pricing
**Severity:** blocks configuration of pricing (no new or changed pricing procedure can be saved)

## Problem

Any save of a pricing procedure fails with:

> Ensure that the lookup table in the ListPrice step is valid and try again.

## Steps to reproduce (UI, no customisation involved)

1. Setup → Pricing Procedures → **RLM Revenue Management Default Pricing Procedure**.
2. **Clone** it (any name) → Save → error above.
3. Or open it in the builder, deactivate / edit (even only the description), re-select the lookup tables of the three
   List Price steps, Save → same error.

Same result through the Metadata API (`sf project deploy start --dry-run`) for: a new procedure, an update with only
the description changed, and variants with the contract-price and cost-book List Price steps removed. Re-deploying
the procedure **unchanged** validates.

## Already checked

| Check | Result |
|---|---|
| Decision tables used by the List Price steps (`Price_Book_Entry_Decision_Table_v2` 0lDhm00000017XREAY, `RLM_CostBookEntries` 0lDhm00000017XtEAI, `Contract_Pricing_Entries_Decision_Table` 0lDhm00000017XZEAY) | All **Active**; Ids match the procedure's `LookUpId` |
| Setup → Salesforce Pricing Setup → **Sync Pricing Data** | Run; no change |
| **Refresh** on each of the three decision tables (App Launcher → Decision Tables) | Run; no change |
| Context definition `RLM_SalesTransactionContext` | **Active**, no warnings; inherits `SalesTransactionContext__stdctx`; last modified 11 Nov 2026 12:46 UTC by the additive deploy |
| Deactivate the default procedure, edit, Save | Same error; re-activating the unchanged procedure works |
| Re-selecting the lookup tables in the builder | Same error |
| API version | Retrieve/deploy at the org's version 68.0 |

## Recent changes in the org (for context)

- Records loaded through the API: products, price book entries (352), price adjustment schedules (3) with tiers (432),
  a price book, promotions and coupons.
- Context definition `RLM_SalesTransactionContext`: two **additive** line attributes (`MbVolumeLocationCount`,
  `MbBillingPeriodMonths`) hydrated from QuoteLineItem formula fields, deployed 11 Nov 2026 12:45 UTC. The Clone
  failure was first seen after this; whether it existed before is unknown. Removing the attributes by deploy is
  refused ("Context Attribute is being delete …").

## Ask

1. Why the List Price lookup validation fails for every save, and how to rebind / repair it.
2. Whether additive context attributes can affect List Price lookup validation.
3. How to remove the two context attributes if needed.
