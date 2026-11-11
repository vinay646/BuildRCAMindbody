# Mindbody on Salesforce ARM – Build

Salesforce source for building the **Mindbody ARM Requirements Spec** in a Revenue Cloud (ARM) org,
phase by phase. Plan, feasibility and user stories: [docs/BUILD_PLAN.md](docs/BUILD_PLAN.md).
Requirement checks against the org live in the companion repo `vinay646/mindbody-arm-req-checker`.

## Status

| Phase | Scope | State |
|---|---|---|
| 0 | Org setup (ARM + Billing, multi-currency USD/GBP/AUD/EUR) | To do in the org |
| 1 | Account hierarchy, payer model, addresses (US-01..US-04, RLP-01) | Drafted – not yet deployed |
| 2 | Product catalog (PD-01..PD-09, PD-14) | Drafted – not yet deployed |
| 3 | Pricing procedure | Discount tables drafted as custom metadata |
| 4–10 | Rules, quoting, orders, billing, amendments, rollups, integrations | Not started |

## Deploy and load

```bash
sf org login web --alias mindbody-dev --instance-url https://test.salesforce.com
sf project deploy start --target-org mindbody-dev
```

Then load the data one step at a time (each step is safe to re-run):

```bash
for step in accounts catalog products bundles attributes pricebooks; do
  echo "MindbodyBuildLoader.run('$step');" | sf apex run --target-org mindbody-dev
done
```

All catalog, price and demo account data is in
`force-app/main/default/staticresources/MB_Build_Data.json` – edit it there and redeploy.
