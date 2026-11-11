# Reference: the org's standard pricing setup

Retrieved read-only from ExploremoreRCA with the `explore` workflow action (11 Nov 2026), one line per file:

- `RLM_DefaultPricingProcedure.expressionSetDefinition` – the standard *RLM Revenue Management Default Pricing Procedure*
- `RLM_SalesTransactionContext.contextDefinition` – the org's sales transaction context (extension of Salesforce's
  standard `SalesTransactionContext__stdctx`)

`scripts/build_pricing_procedure.py` builds the Mindbody procedure and the context change from these files, so
the build can be regenerated for another org (re-run `explore`, replace these files, set the schedule Ids).
