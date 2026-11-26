#!/usr/bin/env bash
# CHANGES QA pricing: adds the "Mindbody line term from quote" step to RLM_DefaultPricingProcedure version 4 (in place), deploys it, then activates version 4
export VER=4
./scripts/usage/qa_pp_v5.sh
sleep 10
./scripts/usage/activate_version.sh 4
