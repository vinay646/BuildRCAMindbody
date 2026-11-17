#!/usr/bin/env python3
"""Version 5 of RLM_DefaultPricingProcedure = active version 4 + "existing + new locations" volume count, and the
standard volume step restored. Replaces the earlier floor-price draft of version 5 (that draft broke context hydration
and was never activated; it stays in git history).

Changes against version 4 (all standard elements):
  1. List Group "Mindbody new locations – reset": every line, Formula 0 -> line tag MbNewLocationQty.
  2. List Group "Mindbody new locations – new core plan lines": lines with ProductCode MB-STR/ACC/ULT/ENT and
     SalesTransactionActionType blank or 'Add', Formula LineItemQuantity -> MbNewLocationQty.
  3. Aggregate Price "Mindbody new locations on quote": SUM(MbNewLocationQty) over all lines -> header tag
     MbNewLocationsOnQuote (no grouping, like the standard "total amount" aggregate).
  4. List Group "Mindbody volume count": every line, Formula MbHierarchyLocationCount + MbNewLocationsOnQuote ->
     line tag MbVolumeLocationCount (existing, unused attribute).
  5. Volume group: the Mindbody location step reads MbVolumeLocationCount; the standard Salesforce volume step is added
     back exactly as in version 1 (schedule VolumePASIdConstant, bounds = line quantity) so future quantity-based
     volume products only need tiers. Order: Mindbody location volume, standard volume, contract term, billing frequency.
Source: the org's version 4 as retrieved (BASE env var or the default scratch path); output: deploy/pricing-v5.
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = Path(os.environ.get("BASE", ROOT / "deploy/org-retrieved/RLM_DefaultPricingProcedure.expressionSetDefinition"))
OUT = ROOT / "deploy/pricing-v5/main/default/expressionSetDefinition/RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml"
V4 = "RLM_DefaultPricingProcedure_RLM_Revenue_Management_Default_Pricing_Procedure_V40"
V5 = "RLM_DefaultPricingProcedure_RLM_Revenue_Management_Default_Pricing_Procedure_V50"
VOLUME_GROUP = "Applyvolumebaseddiscountstolineswithoutcontractorlasttrxnpricing"
STD_STEP = "Calculatenetunitpriceandnettotalpriceaftervolumebaseddiscount"
FIRST_SEQ = 20  # the volume group's current top-level sequence; the 4 new top-level steps go in front of it
CORE = ["MB-STR", "MB-ACC", "MB-ULT", "MB-ENT"]
FLAGS = ("<shouldExposExecPathMsgOnly>true</shouldExposExecPathMsgOnly><shouldExposeConditionDetails>false</shouldExposeConditionDetails>"
         "<shouldShowExplExternally>false</shouldShowExplExternally>")


def P(n, t, v, out=False):
    return (f"<parameters><input>{'false' if out else 'true'}</input><name>{n}</name><output>{'true' if out else 'false'}</output>"
            f"<type>{t}</type><value>{v}</value></parameters>")


def crit(i, field, op, value=None):
    val = f"<value>{value}</value><valueType>Literal</valueType>" if value is not None else ""
    return f"<criteria><operator>{op}</operator><sequenceNumber>{i}</sequenceNumber><sourceFieldName>{field}</sourceFieldName>{val}</criteria>"


def group(name, label, seq, logic, criteria, formula, output):
    return (
        f"<steps><hasNestedExplainability>false</hasNestedExplainability><label>{label}</label><name>{name}</name>"
        f"<resultIncluded>false</resultIncluded><sequenceNumber>{seq}</sequenceNumber>{FLAGS}<stepType>ListGroup</stepType></steps>"
        f"<steps><advancedCondition><conditionLogic>{logic}</conditionLogic>{''.join(criteria)}</advancedCondition>"
        f"<hasNestedExplainability>false</hasNestedExplainability><label>Filter lines – {label}</label><name>{name}Filter</name>"
        f"<parentStep>{name}</parentStep><resultIncluded>false</resultIncluded><sequenceNumber>1</sequenceNumber>{FLAGS}"
        f"<stepType>AdvancedListFilter</stepType></steps>"
        f"<steps><actionType>FormulaBasedPricing</actionType><customElement>"
        + P("formula-section-0-input", "Formula", formula) + P("formulaSectionCount", "Literal", "1")
        + P("HideWaterfall", "Literal", "true") + P("sectionCount", "Literal", "0") + P("selectedFunction", "Literal", "Get")
        + P("IsRealTime", "Literal", "false") + P("formula-section-0-output", "Parameter", output, True)
        + P("Output Variable", "Parameter", output, True)
        + f"</customElement><description>Formula Based Pricing</description><hasNestedExplainability>false</hasNestedExplainability>"
        f"<label>Set {output}</label><name>{name}Formula</name><parentStep>{name}</parentStep><resultIncluded>false</resultIncluded>"
        f"<sequenceNumber>2</sequenceNumber>{FLAGS}<stepType>BusinessKnowledgeModel</stepType></steps>")


ALL_LINES = ("1 OR 2", [crit(1, "ProductCode", "IsNull"), crit(2, "ProductCode", "NotEquals", "&apos;MB-NONE&apos;")])
NEW_CORE = ("(1 OR 2 OR 3 OR 4) AND (5 OR 6)",
            [crit(i + 1, "ProductCode", "Equals", f"&apos;{c}&apos;") for i, c in enumerate(CORE)]
            + [crit(5, "SalesTransactionActionType", "IsNull"), crit(6, "SalesTransactionActionType", "Equals", "&apos;Add&apos;")])

AGGREGATE = (
    "<steps><actionType>GroupingAndAggregatePricing</actionType><customElement>"
    + P("section-count", "Literal", "1") + P("section-0-group-count", "Literal", "0") + P("section-0-aggr-func", "Literal", "SUM")
    + P("section-0-aggr-func-tag-type", "Literal", "Number") + P("section-0-aggr-func-tag", "Parameter", "MbNewLocationQty")
    + P("section-0-output-type", "Literal", "Number")
    + P("condition-0-input", "Parameter", "MbNewLocationQty") + P("condition-0-operator", "Literal", "isNotNull")
    + P("condition-0-input-data-type", "Literal", "Number")
    + P("write-back-data-type", "Literal", "Text") + P("rollup-condition-data-type", "Literal", "Text")
    + P("where-condition-count", "Literal", "1") + P("RollUpPrice", "Literal", "false")
    + P("section-0-output", "Parameter", "MbNewLocationsOnQuote", True)
    + "</customElement><description>Aggregate Price</description><hasNestedExplainability>false</hasNestedExplainability>"
    "<label>Mindbody new locations on quote</label><name>MindbodyNewLocationsOnQuote</name><resultIncluded>false</resultIncluded>"
    f"<sequenceNumber>{FIRST_SEQ + 2}</sequenceNumber>{FLAGS}<stepType>BusinessKnowledgeModel</stepType></steps>")


def outer(st):
    return re.sub(r"<customElement>.*?</customElement>", "", st, flags=re.S)


def set_param(st, name, value):
    out, n = re.subn(rf"(<name>{re.escape(name)}</name>\s*<output>[^<]*</output>\s*<type>[^<]*</type>\s*<value>)[^<]*(</value>)",
                     rf"\g<1>{value}\g<2>", st)
    if n == 0:
        sys.exit(f"parameter {name} not found")
    return out


def set_tag(st, tag, value, last=False):
    o = outer(st)
    matches = list(re.finditer(rf"<{tag}>[^<]*</{tag}>", o))
    m = matches[-1] if last else matches[0]
    old = m.group(0)
    # replace that occurrence in the full step (outside customElement it is unique enough when taken from the end)
    idx = st.rfind(old) if last else st.find(old, st.find("</customElement>") if "</customElement>" in st else 0)
    return st[:idx] + f"<{tag}>{value}</{tag}>" + st[idx + len(old):]


def main():
    s = BASE.read_text()
    v1 = [x for x in re.findall(r"<versions>.*?</versions>", s, re.S) if "<versionNumber>1</versionNumber>" in x][0]
    v = [x for x in re.findall(r"<versions>.*?</versions>", s, re.S) if f"<fullName>{V4}</fullName>" in x][0]
    std = [st for st in re.findall(r"<steps>.*?</steps>", v1, re.S) if f"<name>{STD_STEP}</name>" in st][0]

    steps = re.findall(r"<steps>.*?</steps>", v, re.S)
    new_steps = []
    for st in steps:
        o = outer(st)
        parent = re.search(r"<parentStep>(.*?)</parentStep>", o)
        name = re.findall(r"<name>(.*?)</name>", o)[-1]
        if parent is None:  # top level: shift from the volume group on
            seq = int(re.findall(r"<sequenceNumber>(\d+)</sequenceNumber>", o)[-1])
            if seq >= FIRST_SEQ:
                st = set_tag(st, "sequenceNumber", seq + 4, last=True)
        elif parent.group(1) == VOLUME_GROUP:
            if name == STD_STEP:  # current Mindbody location step: new name, bounds = volume count
                st = set_param(st, "LowerBound", "MbVolumeLocationCount")
                st = set_param(st, "UpperBound", "MbVolumeLocationCount")
                st = st.replace(f"<name>{STD_STEP}</name>", "<name>MindbodyLocationVolumeDiscount</name>")
                st = st.replace("<resultIncluded>true</resultIncluded>", "<resultIncluded>false</resultIncluded>")
            elif name == "MindbodyContractTermDiscount":
                st = set_tag(st, "sequenceNumber", 4, last=True)
            elif name == "MindbodyBillingFrequencyDiscount":
                st = set_tag(st, "sequenceNumber", 5, last=True)
        new_steps.append(st)
        if parent is not None and parent.group(1) == VOLUME_GROUP and name == STD_STEP:
            new_steps.append(set_tag(std, "sequenceNumber", 3, last=True))  # standard step, as Salesforce ships it

    added = (group("MindbodyNewLocationsReset", "Mindbody new locations – reset", FIRST_SEQ, *ALL_LINES, "0", "MbNewLocationQty")
             + group("MindbodyNewLocationsCore", "Mindbody new locations – new core plan lines", FIRST_SEQ + 1, *NEW_CORE,
                     "LineItemQuantity", "MbNewLocationQty")
             + AGGREGATE
             + group("MindbodyVolumeCount", "Mindbody volume count", FIRST_SEQ + 3, *ALL_LINES,
                     "MbHierarchyLocationCount + MbNewLocationsOnQuote", "MbVolumeLocationCount"))

    head = v[: v.find("<steps>")]
    tail = v[v.rfind("</steps>") + len("</steps>"):]
    body = "".join(new_steps)
    v5 = head + added + body + tail
    v5 = v5.replace(f"<fullName>{V4}</fullName>", f"<fullName>{V5}</fullName>", 1)
    v5 = re.sub(r"<label>RLM Revenue Management Default Pricing Procedure V4</label>",
                "<label>RLM Revenue Management Default Pricing Procedure V5</label>", v5, count=1)
    v5 = re.sub(r"<rank>4</rank>", "<rank>5</rank>", v5, count=1)
    v5 = re.sub(r"<versionNumber>4</versionNumber>", "<versionNumber>5</versionNumber>", v5, count=1)
    v5 = re.sub(r"<status>Active</status>", "<status>Draft</status>", v5, count=1)
    v5 = re.sub(r"<description>[^<]*</description>",
                "<description>Default pricing + Mindbody discounts: location volume (hierarchy + new locations on the quote), "
                "standard quantity volume, contract term, billing frequency; promotions.</description>", v5, count=1)

    wrapper = OUT.read_text()
    w_head = wrapper[: wrapper.find("<versions>")]
    w_tail = wrapper[wrapper.rfind("</versions>") + len("</versions>"):]
    OUT.write_text(w_head + v5 + w_tail)
    print("version 5 written:", len(re.findall(r"<steps>", v5)), "steps (v4 had", len(steps), ")")


if __name__ == "__main__":
    main()
