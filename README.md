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

## Connect GitHub to the org (one time)

1. On your computer, install the Salesforce CLI (`npm install --global @salesforce/cli`) and log in to the new org:
   ```bash
   sf org login web --alias mindbody-dev --instance-url https://test.salesforce.com
   ```
   Use `https://login.salesforce.com` for a production or trial org.
2. Print the org's auth URL and copy the **Sfdx Auth Url** value (starts with `force://`):
   ```bash
   sf org display --target-org mindbody-dev --verbose
   ```
3. In GitHub: **Settings → Secrets and variables → Actions → New repository secret**, name `SFDX_AUTH_URL`, paste the value.
   Treat it like a password: it logs in as you.

## Run from GitHub

**Actions → Salesforce build → Run workflow**, pick an action:

| Action | What it does | Changes the org? |
|---|---|---|
| `readiness` | Phase 0: lists what the org has turned on (ARM objects, currencies, …) | No |
| `validate` | Check-only deploy of `force-app` | No |
| `deploy` | Deploys `force-app` and assigns permission set *Mindbody ARM Build* to you | Yes |
| `load` | Runs one loader step (pick `step`) | Yes |
| `load-all` | Runs every loader step in order | Yes |
| `deploy-and-load` | Both | Yes |

Pull requests that change `force-app` run `validate` automatically. Suggested first run: `readiness` → fix what it
reports in Setup → `validate` → `deploy` → `load` step by step (`accounts` first).

## Deploy and load from your computer

```bash
sf org login web --alias mindbody-dev --instance-url https://test.salesforce.com
sf project deploy start --target-org mindbody-dev
sf org assign permset --name Mindbody_ARM_Build --target-org mindbody-dev
```

Then load the data one step at a time (each step is safe to re-run):

```bash
for step in accounts catalog products bundles attributes pricebooks; do
  echo "MindbodyBuildLoader.run('$step');" | sf apex run --target-org mindbody-dev
done
```

All catalog, price and demo account data is in
`force-app/main/default/staticresources/MB_Build_Data.json` – edit it there and redeploy.
