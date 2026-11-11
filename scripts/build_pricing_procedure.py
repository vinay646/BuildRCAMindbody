#!/usr/bin/env python3
"""Adds the Mindbody pricing steps to the org's default pricing procedure and builds the context change
(from the org's own files in reference/).

Why the existing procedure is updated instead of a new one: in ExploremoreRCA, creating a NEW pricing procedure
fails - by deploy and by Setup > Clone alike - with "Ensure that the lookup table in the ListPrice step is valid",
even after Sync Pricing Data, while an update of the existing procedure deploys. Mindbody's tiers only exist for
Mindbody products, so other products priced by this procedure are not affected.

Standard steps only. Changes to the standard procedure:
  * Volume Discount step: schedule = Mindbody Hierarchy Volume; tier bounds read the line's
    MbVolumeLocationCount (= quote's hierarchy location count + the line's quantity, RLP-01 / PRC-04).
  * Two copies of that step right after it:
      Mindbody Contract Term     – tier bounds = ItemSubscriptionTerm (standard tag)           (PRC-06)
      Mindbody Billing Frequency – tier bounds = MbBillingPeriodMonths (1 / 3 / 6 / 12)        (PRC-06)
Context change (additive): two line attributes hydrated from QuoteLineItem formula fields.

Usage: python3 scripts/build_pricing_procedure.py VOLUME_ID TERM_ID FREQUENCY_ID
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "reference"
OUT = ROOT / "force-app/main/default"
STD = "RLM_DefaultPricingProcedure"
NAME = STD  # updated in place (see module docstring)
VOLUME_STEP = "Calculatenetunitpriceandnettotalpriceaftervolumebaseddiscount"
VOLUME_GROUP = "Applyvolumebaseddiscountstolineswithoutcontractorlasttrxnpricing"
# Left out: index-based price revision (consumer price index). Not in the Mindbody spec – renewal uplift (LCM-13)
# uses the standard Uplift step, which stays – and the metadata API rejects this step's parameters on deploy
# ("ValidStartDate isn't a valid variable name").
DROP_GROUP = "Applypricerevisionforlineswithsubscriptionandwithoutderivedpricing"
LINE_ATTRS = [  # (context attribute / tag, QuoteLineItem field)
    ("MbVolumeLocationCount", "Volume_Location_Count__c"),
    ("MbBillingPeriodMonths", "Billing_Period_Months__c"),
]
HIDDEN_HEADER_STD_ATTRS = []  # none at the org API version (68.0); an older retrieve misses newer standard attributes
XML_HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'


def one(pattern, text, what):
    found = re.findall(pattern, text, flags=re.S)
    if len(found) != 1:
        sys.exit(f"expected exactly one {what}, found {len(found)}")
    return found[0]


def param_value(step, name, value):
    """Set a step parameter's <value>, failing loudly if the parameter is not there."""
    pat = rf"(<parameters><input>true</input><name>{re.escape(name)}</name><output>false</output><type>\w+</type><value>)[^<]*(</value>)"
    new, n = re.subn(pat, rf"\g<1>{value}\g<2>", step)
    if n != 1:
        sys.exit(f"parameter {name}: expected 1 match, found {n}")
    return new


def step_field(step, field, value):
    tail_start = step.rfind("</customElement>")
    head, tail = step[:tail_start], step[tail_start:]
    tail, n = re.subn(rf"<{field}>[^<]*</{field}>", f"<{field}>{value}</{field}>", tail, count=1)
    if n != 1:
        sys.exit(f"step field {field} not found")
    return head + tail


def drop_group(s, group):
    """Remove a top-level list group and its children; close the gap in the top-level sequence numbers."""
    all_steps = re.findall(r"<steps>.*?</steps>", s, flags=re.S)
    def tail(st):
        return st.split("</customElement>")[-1]
    group_step = [st for st in all_steps if f"<name>{group}</name>" in tail(st) and "<parentStep>" not in tail(st)]
    if len(group_step) != 1:
        sys.exit(f"group {group} not found")
    seq = int(re.search(r"<sequenceNumber>(\d+)</sequenceNumber>", tail(group_step[0])).group(1))
    removed = 0
    for st in all_steps:
        t = tail(st)
        if st is group_step[0] or f"<parentStep>{group}</parentStep>" in t:
            s = s.replace(st, "", 1)
            removed += 1
        elif "<parentStep>" not in t:
            n = int(re.search(r"<sequenceNumber>(\d+)</sequenceNumber>", t).group(1))
            if n > seq:
                s = s.replace(st, st[:len(st) - len(t)] + t.replace(f"<sequenceNumber>{n}</sequenceNumber>",
                                                                    f"<sequenceNumber>{n - 1}</sequenceNumber>", 1), 1)
    if removed < 2:
        sys.exit(f"group {group}: removed only {removed} steps")
    return s


def constant(name, value, description):
    return (f"<variables><collection>false</collection><dataType>Text</dataType><decimalPlaces>2</decimalPlaces>"
            f"<description>{description}</description><input>false</input><name>{name}</name><output>false</output>"
            f"<type>Constant</type><value>{value}</value></variables>")


def build_procedure(volume_id, term_id, frequency_id):
    s = (REF / f"{STD}.expressionSetDefinition").read_text()
    steps = re.findall(r"<steps>.*?</steps>", s, flags=re.S)
    vol = one(rf"<steps>(?:(?!</steps>).)*?<name>{VOLUME_STEP}</name>.*?</steps>", s, "volume step")

    def discount_step(name, label, desc, pas_const, bound_tag, seq):
        st = param_value(vol, "PriceAdjustmentScheduleId", pas_const)
        st = param_value(st, "LowerBound", bound_tag)
        st = param_value(st, "UpperBound", bound_tag)
        st = step_field(st, "description", desc)
        st = step_field(st, "label", label)
        st = step_field(st, "name", name)
        st = step_field(st, "sequenceNumber", str(seq))
        return st

    new_steps = [
        discount_step(VOLUME_STEP, "Mindbody volume discount by hierarchy locations",
                      "Volume Discount – Mindbody Hierarchy Volume (PRC-04, RLP-01)", "MbHierarchyVolumePASId",
                      "MbVolumeLocationCount", 2),
        discount_step("MindbodyContractTermDiscount", "Mindbody term discount by contract term",
                      "Volume Discount – Mindbody Contract Term (PRC-06)", "MbContractTermPASId",
                      "ItemSubscriptionTerm", 3),
        discount_step("MindbodyBillingFrequencyDiscount", "Mindbody billing frequency discount",
                      "Volume Discount – Mindbody Billing Frequency (PRC-06)", "MbBillingFrequencyPASId",
                      "MbBillingPeriodMonths", 4),
    ]
    for st in new_steps:
        if f"<parentStep>{VOLUME_GROUP}</parentStep>" not in st:
            sys.exit("cloned step lost its parent group")
    s = s.replace(vol, "".join(new_steps), 1)

    s = s.replace("<description>Revenue Management Default Pricing Procedure</description>",
                  "<description>Revenue Management Default Pricing Procedure + Mindbody hierarchy volume, contract term and "
                  "billing frequency discounts on standard price adjustment schedules (spec 12.2).</description>", 1)
    # schedule constants
    consts = (constant("MbHierarchyVolumePASId", volume_id, "Mindbody Hierarchy Volume schedule")
              + constant("MbContractTermPASId", term_id, "Mindbody Contract Term schedule")
              + constant("MbBillingFrequencyPASId", frequency_id, "Mindbody Billing Frequency schedule"))
    s = s.replace("<variables>", consts + "<variables>", 1)
    path = OUT / "expressionSetDefinition" / f"{NAME}.expressionSetDefinition-meta.xml"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(XML_HEAD + s + "\n")
    return path, len(steps), len(re.findall(r"<steps>", s))


def build_context():
    c = (REF / "RLM_SalesTransactionContext.contextDefinition").read_text()
    # 1. attributes on the SalesTransactionItem node: next to the org's own RLM_Distributor_Unit_Price__c
    anchor_attr = one(r"<contextAttributes><contextTags><title>RLM_Distributor_Unit_Price__c</title></contextTags>.*?</contextAttributes>",
                      c, "RLM_Distributor_Unit_Price__c attribute")
    add_attrs = "".join(
        f"<contextAttributes><contextTags><title>{a}</title></contextTags><dataType>number</dataType>"
        f"<fieldType>input</fieldType><key>false</key><title>{a}</title><transient>false</transient>"
        f"<value>false</value></contextAttributes>" for a, _ in LINE_ATTRS)
    c = c.replace(anchor_attr, anchor_attr + add_attrs, 1)
    # 1b. system attributes the org has but a retrieve does not return: put them back, or the deploy reads
    #     as deleting them ("Context Attribute is being delete IsContextInUse__std from node SalesTransaction")
    header_attr = one(r"<contextAttributes><contextTags><title>RLM_Distributor_Account__c</title></contextTags>.*?</contextAttributes>",
                      c, "RLM_Distributor_Account__c attribute")
    for name, dtype in HIDDEN_HEADER_STD_ATTRS:
        if f"<title>{name}</title></contextTags>" not in c:
            inherited = f"SalesTransactionContext__stdctx/version/SalesTransaction/{name}"
            c = c.replace(header_attr, header_attr + (
                f"<contextAttributes><contextTags><inheritedFrom>{inherited}/{name}</inheritedFrom><title>{name}</title></contextTags>"
                f"<dataType>{dtype}</dataType><fieldType>input</fieldType><inheritedFrom>{inherited}</inheritedFrom>"
                f"<key>false</key><title>{name}</title><transient>false</transient><value>false</value></contextAttributes>"), 1)
    # 2. hydration from QuoteLineItem in the quote mapping (same place as RLM_Distributor_Unit_Price__c)
    anchor_map = one(r"<contextAttributeMappings><contextAttrHydrationDetails><objectName>QuoteLineItem</objectName>"
                     r"<queryAttribute>RLM_Distributor_Unit_Price__c</queryAttribute></contextAttrHydrationDetails>.*?</contextAttributeMappings>",
                     c, "RLM_Distributor_Unit_Price__c quote line mapping")
    add_maps = "".join(
        f"<contextAttributeMappings><contextAttrHydrationDetails><objectName>QuoteLineItem</objectName>"
        f"<queryAttribute>{fld}</queryAttribute></contextAttrHydrationDetails><contextAttribute>{a}</contextAttribute>"
        f"<contextInputAttributeName>{fld}</contextInputAttributeName></contextAttributeMappings>" for a, fld in LINE_ATTRS)
    c = c.replace(anchor_map, anchor_map + add_maps, 1)
    path = OUT / "contextDefinitions" / "RLM_SalesTransactionContext.contextDefinition-meta.xml"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(XML_HEAD + c + "\n")
    return path


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    p, before, after = build_procedure(*sys.argv[1:])
    print(f"{p.relative_to(ROOT)}: {before} standard steps -> {after}")
    print(f"{build_context().relative_to(ROOT)}: +{len(LINE_ATTRS)} line attributes")
