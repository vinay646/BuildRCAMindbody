# Reference: the org's standard pricing setup

Retrieved read-only from ExploremoreRCA at its API version 68.0 with the `explore-context` workflow action (11 Nov 2026), one line per file:

- `RLM_DefaultPricingProcedure.expressionSetDefinition` – the standard *RLM Revenue Management Default Pricing Procedure*
- `RLM_SalesTransactionContext.contextDefinition` – the org's sales transaction context (extension of Salesforce's
  standard `SalesTransactionContext__stdctx`)

`scripts/build_pricing_procedure.py` adds the Mindbody steps to this procedure and builds the context change, so the
build can be regenerated after an upgrade or for another org (`explore-context`, replace these files, `ids`, re-run).
