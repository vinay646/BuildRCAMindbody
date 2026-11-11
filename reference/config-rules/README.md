# Product Configuration Rules – stored definitions (read-only copies)

Product Configuration Rules can only be created in the rule builder (the `ProductConfigurationRule` object is not
createable by API or deploy). After a rule is built, `explore-rules` prints its stored definition
(`ProductConfigurationRule.ConfigurationRuleDefinition`); the copy is kept here so the rule can be rebuilt in
another org.

Product Ids in this org: MB-ULT `01thm000000vXaNAAU`, MB-AIC `01thm000000vXaPAAU`.

| File | Rule | Scope | Criteria | Action |
|---|---|---|---|---|
| CR-05.json | CR 05 AI Concierge included in Ultimate (Active, library *Configurator Rule*) | Transaction | Product = Ultimate and Product = AI Concierge add-on on the quote | Validate, Error: "AI Concierge is already included in Ultimate – remove the AI Concierge add-on" |
