#!/usr/bin/env python3
"""Version 7 of RLM_DefaultPricingProcedure = version 6 + renewal uplift (MR-122 4.17).

New top-level List Group "Mindbody renewal uplift", right after the standard "Apply uplifts to ramped subscriptions items
during amendment" group, built the same way:
  filter: renewal lines (SalesTransactionActionType = 'Renew') with a Unit Price Uplift and quantity > 0
  formula: NetUnitPrice + NetUnitPrice * ItemUnitPriceUplift__std  (the standard uplift formula)
Assets and contracts get a 5% Unit Price Uplift (flows MB Asset Renewal Term / MB Order Auto Activate).
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "deploy/pricing-v6/main/default/expressionSetDefinition/RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml"
OUT = ROOT / "deploy/pricing-v7/main/default/expressionSetDefinition/RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml"
FLAGS = ("<shouldExposExecPathMsgOnly>true</shouldExposExecPathMsgOnly><shouldExposeConditionDetails>false</shouldExposeConditionDetails>"
         "<shouldShowExplExternally>false</shouldShowExplExternally>")
P = lambda n, t, v, out=False: (f"<parameters><input>{'false' if out else 'true'}</input><name>{n}</name><output>{'true' if out else 'false'}</output>"
                                f"<type>{t}</type><value>{v}</value></parameters>")

s = SRC.read_text()
s = s.replace("_V60</fullName>", "_V70</fullName>").replace("Pricing Procedure V6</label>", "Pricing Procedure V7</label>")
s = s.replace("<rank>6</rank>", "<rank>7</rank>").replace("<versionNumber>6</versionNumber>", "<versionNumber>7</versionNumber>")
s = s.replace("<status>Active</status>", "<status>Draft</status>", 1)
s = s.replace("; promotions.</description>", "; promotions; renewal uplift.</description>")
flat = re.sub(r">\s+<", "><", s)
SEQ = int(re.search(r"<name>Applyupliftstorampedsubscriptionsitemsduringamendment</name><resultIncluded>false</resultIncluded><sequenceNumber>(\d+)</sequenceNumber>", flat).group(1)) + 1
assert "MindbodyRenewalUplift" not in s


def shift(m):
    block = m.group(0)
    outer = re.sub(r"<customElement>.*?</customElement>", "", block, flags=re.S)
    if "<parentStep>" in outer:
        return block
    n = int(re.search(r"<sequenceNumber>(\d+)</sequenceNumber>", outer).group(1))
    if n < SEQ:
        return block
    tail = block.rfind("<sequenceNumber>")
    return block[:tail] + block[tail:].replace(f"<sequenceNumber>{n}</sequenceNumber>", f"<sequenceNumber>{n + 1}</sequenceNumber>", 1)


s = re.sub(r"<steps>(?:(?!<steps>).)*?</steps>", shift, s, flags=re.S)
name = "MindbodyRenewalUplift"
crit = lambda i, f, op, v=None, vt="Literal": (f"<criteria><operator>{op}</operator><sequenceNumber>{i}</sequenceNumber><sourceFieldName>{f}</sourceFieldName>"
                                              + (f"<value>{v}</value><valueType>{vt}</valueType>" if v is not None else "") + "</criteria>")
new = (
    f"<steps><hasNestedExplainability>false</hasNestedExplainability><label>Mindbody renewal uplift</label><name>{name}</name>"
    f"<resultIncluded>false</resultIncluded><sequenceNumber>{SEQ}</sequenceNumber>{FLAGS}<stepType>ListGroup</stepType></steps>"
    f"<steps><advancedCondition><conditionLogic>1 AND 2 AND 3 AND 4</conditionLogic>"
    + crit(1, "ItemUnitPriceUplift__std", "IsNotNull") + crit(2, "ItemUnitPriceUplift__std", "GreaterThan", "0")
    + crit(3, "SalesTransactionActionType", "Equals", "&apos;Renew&apos;") + crit(4, "LineItemQuantity", "GreaterThan", "0")
    + f"</advancedCondition><hasNestedExplainability>false</hasNestedExplainability><label>Filter renewal lines with an uplift</label>"
    f"<name>{name}Filter</name><parentStep>{name}</parentStep><resultIncluded>false</resultIncluded><sequenceNumber>1</sequenceNumber>{FLAGS}"
    f"<stepType>AdvancedListFilter</stepType></steps>"
    f"<steps><actionType>FormulaBasedPricing</actionType><customElement>"
    + P("formula-section-0-input", "Formula", "NetUnitPrice + NetUnitPrice * ItemUnitPriceUplift__std") + P("writeBackData", "Literal", "[]")
    + P("formulaSectionCount", "Literal", "1") + P("HideWaterfall", "Literal", "false") + P("sectionCount", "Literal", "0")
    + P("selectedFunction", "Literal", "Get") + P("IsRealTime", "Literal", "false")
    + P("formula-section-0-output", "Parameter", "NetUnitPrice", out=True) + P("Output Variable", "Parameter", "NetUnitPrice", out=True)
    + f"</customElement><description>Formula Based Pricing</description><hasNestedExplainability>false</hasNestedExplainability>"
    f"<label>Renewal uplift</label><name>{name}Formula</name><parentStep>{name}</parentStep><resultIncluded>false</resultIncluded>"
    f"<sequenceNumber>2</sequenceNumber>{FLAGS}<stepType>BusinessKnowledgeModel</stepType></steps>"
)
i = s.index("<steps>")
s = s[:i] + new + s[i:]
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(s)
print(OUT.relative_to(ROOT), "group at sequence", SEQ)
