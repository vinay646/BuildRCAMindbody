#!/usr/bin/env python3
"""CHANGES the org: links the Mindbody Plans constraint model to the QA org's products (Type links) and bundle components
(Port links) from scripts/qa_build/cml_links_qa.json. Run after the model has been created and its CML saved in Setup
(saving the CML after links exist fails). Existing links are kept; only missing ones are created."""
import json, subprocess
L = json.load(open('scripts/qa_build/cml_links_qa.json'))


def run(a):
    r = subprocess.run(a, capture_output=True, text=True); return r.stdout + r.stderr


def q(soql):
    try:
        return json.loads(run(["sf", "data", "query", "--query", soql, "--target-org", "target", "--json"]))["result"]["records"]
    except Exception as e:
        print("query error", soql[:80], e); return []


want = L['apiName'].replace('_', '').lower()
sets = [s for s in q("SELECT Id, Name, ApiName FROM ExpressionSet WHERE InterfaceSourceType = 'Constraint'") if s['ApiName'].replace('_', '').lower() == want]
if not sets:
    raise SystemExit("Constraint model Mindbody_Plans not found – create it in Setup and save the CML first.")
sid = sets[0]['Id']; print("model", sets[0]['Name'], sid)
prod = {p['ProductCode']: p['Id'] for p in q("SELECT Id, ProductCode FROM Product2 WHERE ProductCode LIKE 'MB-%'")}
prc = {(c['ParentProduct']['ProductCode'], c['ChildProduct']['ProductCode']): c['Id']
       for c in q("SELECT Id, ParentProduct.ProductCode, ChildProduct.ProductCode FROM ProductRelatedComponent WHERE ParentProduct.ProductCode LIKE 'MB-%'")}
have = {(x['ConstraintModelTag'], x['ConstraintModelTagType']) for x in q(f"SELECT ConstraintModelTag, ConstraintModelTagType FROM ExpressionSetConstraintObj WHERE ExpressionSetId = '{sid}'")}
rows = [(t, 'Type', prod.get(c), c) for t, c in L['types'].items()] + [(p['tag'], 'Port', prc.get((p['parent'], p['child'])), f"{p['parent']}>{p['child']}") for p in L['ports']]
ok = skip = bad = 0
for tag, kind, ref, what in rows:
    if (tag, kind) in have:
        skip += 1; continue
    if not ref:
        print("   MISSING in org:", kind, tag, what); bad += 1; continue
    out = run(["sf", "data", "create", "record", "--sobject", "ExpressionSetConstraintObj", "--values",
               f"ExpressionSetId={sid} ConstraintModelTag={tag} ConstraintModelTagType={kind} ReferenceObjectId={ref}", "--target-org", "target", "--json"])
    if '"status": 0' in out:
        ok += 1
    else:
        bad += 1; print("   FAIL", kind, tag, what, json.loads(out).get("message", out)[:300] if out.strip().startswith("{") else out[:300])
print(f"links created {ok}, already there {skip}, failed {bad} (of {len(rows)})")
