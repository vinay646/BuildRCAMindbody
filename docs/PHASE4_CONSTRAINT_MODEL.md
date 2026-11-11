![Company logo](../logo.png)

# Phase 4 – Mindbody Plans constraint model (CML)

Standard ARM constraint model, built the same way as the org's own *QuantumBit Bundle* model: a virtual `Quote`
type that sees every quote line, and one CML type per product. The CML is in [`cml/MindbodyPlans.cml`](../cml/MindbodyPlans.cml).

## What the model checks

| Rule | Check | Message (Error) |
|---|---|---|
| CR-05 / CAT-05 | Ultimate and AI Concierge add-on on the same quote | AI Concierge is already included in Ultimate – remove the AI Concierge add-on. |
| CR-04 / CFG-03 | Starter and AI Concierge add-on | Starter can't add AI Concierge – choose Accelerate or Ultimate. |
| CR-04 / CFG-03 | Starter and Branded app | Starter can't add Branded app – choose Accelerate or Ultimate. |
| CR-07 | More than one Branded app | Branded app is sold once per brand – keep one Branded app on the top account's line group. |
| CR-09 | Card reader, terminal or door kit without Mindbody Payments | Hardware requires Mindbody Payments – add Mindbody Payments (opt in) to the quote. |

Already enforced by the bundles (no CML needed): CR-02/03 included features, CR-06 AI Concierge quantity = locations,
CR-08 Branded app setup fee. Added with phase 5 (needs one line group per location): CR-01 one tier per location,
CFG-13 no duplicate product per Ship-To.

Known limit until phase 5: the checks look at the whole quote, so a multi-location quote with Ultimate at one
location and Accelerate + AI Concierge at another is flagged by CR-05. They move to the line group in phase 5.

## Why part of it is done in Setup

The CML text is stored in `ExpressionSetDefinitionVersion.ConstraintModel`, which is read-only for the API and not
part of the deploy files, so it is pasted once in the constraint model editor. Everything else is automated: the
product links (`ExpressionSetConstraintObj`, loader step `constraints`).

## Steps

1. **Setup → Constraint Models → New** (Revenue Cloud): Name `Mindbody Plans`, API name `MindbodyPlans`,
   context definition `RLM_SalesTransactionContext` (same as the QuantumBit models). Save.
2. Open the version, switch to the **CML editor**, paste the whole of `cml/MindbodyPlans.cml`, **Save**.
   Do not activate yet.
3. GitHub → Actions → Salesforce build → `load`, step `constraints` – links the 9 types to the Mindbody products.
4. Back in the model: **Activate** the version.
5. Test on a quote: Ultimate + AI Concierge add-on → error; Starter + Branded app → error; card reader without
   Mindbody Payments → error; Accelerate + AI Concierge + Branded app → no error.

The configuration rule *CR 05 AI Concierge included in Ultimate* (built earlier in the rule builder) does the same
check as the model's CR-05 line. Keep it until the model is tested, then deactivate it so the rep sees one message.
