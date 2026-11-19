#!/usr/bin/env python3
"""Version 6 of RLM_DefaultPricingProcedure = version 5 + quote-level billing frequency.

New top-level List Group "Mindbody quote billing frequency", placed in front of the billing-months steps:
  filter: recurring lines (line Billing Frequency is Monthly/Quarterly/Semi-Annual/Annual)
          AND the quote's Billing Frequency (header tag MbQuoteBillingFrequency <- Quote.MB_Billing_Frequency__c) is set
  assignment: MbQuoteBillingFrequency -> line tag ItemBillingFrequency (QuoteLineItem.BillingFrequency)
The billing-months steps and the billing frequency discount then read the quote's value.

New top-level List Group "Mindbody quote coupon code", placed in front of "Apply promotions":
  filter: the quote's Coupon Code (header tag MbQuoteCouponCode <- Quote.Coupon_Code__c) is not blank (COUPON_OP)
  assignment: MbQuoteCouponCode -> line tag SalesTransactionItemCouponCode__std, which the rule library maps as
  cartLineCouponCode, so Promotion Execution applies the promotion that owns that coupon to its target products.
STAGE=1 drops the header criteria from the billing filter; STAGE<3 leaves the coupon group out (to bisect a failing deploy).
"""
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "deploy/pricing-v5/main/default/expressionSetDefinition/RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml"
OUT = ROOT / "deploy/pricing-v6/main/default/expressionSetDefinition/RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml"
STAGE = int(os.environ.get("STAGE", "2"))  # 3+ adds the coupon-tag step (does not work: the line coupon lives on a price adjustment record)
SEQ = 16  # first billing-months group
FREQS = ("Monthly", "Quarterly", "Semi-Annual", "Annual")
FLAGS = ("<shouldExposExecPathMsgOnly>true</shouldExposExecPathMsgOnly><shouldExposeConditionDetails>false</shouldExposeConditionDetails>"
         "<shouldShowExplExternally>false</shouldShowExplExternally>")


def P(n, t, v, out=False):
    return (f"<parameters><input>{'false' if out else 'true'}</input><name>{n}</name><output>{'true' if out else 'false'}</output>"
            f"<type>{t}</type><value>{v}</value></parameters>")


def crit(i, field, value):
    return (f"<criteria><operator>Equals</operator><sequenceNumber>{i}</sequenceNumber><sourceFieldName>{field}</sourceFieldName>"
            f"<value>&apos;{value}&apos;</value><valueType>Literal</valueType></criteria>")


s = SRC.read_text()
s = s.replace("_V50</fullName>", "_V60</fullName>").replace("Pricing Procedure V5</label>", "Pricing Procedure V6</label>")
s = s.replace("<rank>5</rank>", "<rank>6</rank>").replace("<versionNumber>5</versionNumber>", "<versionNumber>6</versionNumber>")
s = s.replace("<startDate>2026-11-12T00:00:00.000Z</startDate>", "<startDate>2026-11-18T00:00:00.000Z</startDate>")
s = s.replace("billing frequency; promotions.</description>", "billing frequency (quote-level value applied to the lines); promotions.</description>")


def shift(m):
    block = m.group(0)
    if "<parentStep>" in block:
        return block
    n = int(re.search(r"<sequenceNumber>(\d+)</sequenceNumber>", block).group(1))
    return block if n < SEQ else block.replace(f"<sequenceNumber>{n}</sequenceNumber>", f"<sequenceNumber>{n + 1}</sequenceNumber>", 1)


s = re.sub(r"<steps>(?:(?!<steps>).)*?</steps>", shift, s, flags=re.S)

crits = [crit(i + 1, "ItemBillingFrequency", f) for i, f in enumerate(FREQS)]
logic = "1 OR 2 OR 3 OR 4"
if STAGE >= 2:
    crits += [crit(i + 5, "MbQuoteBillingFrequency", f) for i, f in enumerate(FREQS)]
    logic = "(1 OR 2 OR 3 OR 4) AND (5 OR 6 OR 7 OR 8)"
json2 = ('{&quot;whereConditions&quot;:[{&quot;field&quot;:{&quot;dataType&quot;:&quot;Text&quot;,&quot;name&quot;:&quot;section-0-input1&quot;,'
         '&quot;value&quot;:&quot;MbQuoteBillingFrequency&quot;,&quot;allowCompatibleDataTypes&quot;:true},&quot;value&quot;:{&quot;dataType&quot;:'
         '&quot;Text&quot;,&quot;name&quot;:&quot;section-0-output&quot;,&quot;value&quot;:&quot;ItemBillingFrequency&quot;,'
         '&quot;allowCompatibleDataTypes&quot;:true}}]}')
name = "MindbodyQuoteBillingFrequency"
new = (
    f"<steps><hasNestedExplainability>false</hasNestedExplainability><label>Mindbody quote billing frequency</label><name>{name}</name>"
    f"<resultIncluded>false</resultIncluded><sequenceNumber>{SEQ}</sequenceNumber>{FLAGS}<stepType>ListGroup</stepType></steps>"
    f"<steps><advancedCondition><conditionLogic>{logic}</conditionLogic>{''.join(crits)}</advancedCondition>"
    f"<hasNestedExplainability>false</hasNestedExplainability><label>Filter recurring lines when the quote has a billing frequency</label>"
    f"<name>{name}Filter</name><parentStep>{name}</parentStep><resultIncluded>false</resultIncluded><sequenceNumber>1</sequenceNumber>{FLAGS}"
    f"<stepType>AdvancedListFilter</stepType></steps>"
    f"<steps><actionType>AssignmentElement</actionType><customElement>"
    + P("section-0-input1", "Parameter", "MbQuoteBillingFrequency") + P("sectionCount", "Literal", "1")
    + P("sectionJsonString1", "Literal", "{&quot;whereConditions&quot;:[]}") + P("sectionJsonString2", "Literal", json2)
    + P("section-0-output", "Parameter", "ItemBillingFrequency", out=True)
    + f"</customElement><description>Assignment</description><hasNestedExplainability>false</hasNestedExplainability>"
    f"<label>Line billing frequency = quote billing frequency</label><name>{name}Assign</name><parentStep>{name}</parentStep>"
    f"<resultIncluded>false</resultIncluded><sequenceNumber>2</sequenceNumber>{FLAGS}<stepType>BusinessKnowledgeModel</stepType></steps>"
)
i = s.index("<steps>")
s = s[:i] + new + s[i:]

# ---- quote coupon code -> line coupon code, in front of Apply promotions
if STAGE >= 3:
    PROMO_SEQ = int(re.search(r"<name>Applypromotions</name><resultIncluded>false</resultIncluded><sequenceNumber>(\d+)</sequenceNumber>",
                              re.sub(r">\s+<", "><", s)).group(1))

    def shift2(m):
        block = m.group(0)
        if "<parentStep>" in block:
            return block
        n = int(re.search(r"<sequenceNumber>(\d+)</sequenceNumber>", block).group(1))
        return block if n < PROMO_SEQ else block.replace(f"<sequenceNumber>{n}</sequenceNumber>", f"<sequenceNumber>{n + 1}</sequenceNumber>", 1)

    s = re.sub(r"<steps>(?:(?!<steps>).)*?</steps>", shift2, s, flags=re.S)
    op = os.environ.get("COUPON_OP", "IsNotNull")
    cname = "MindbodyQuoteCouponCode"
    cjson = json2.replace("MbQuoteBillingFrequency", "MbQuoteCouponCode").replace("ItemBillingFrequency", "SalesTransactionItemCouponCode__std")
    coupon = (
        f"<steps><hasNestedExplainability>false</hasNestedExplainability><label>Mindbody quote coupon code</label><name>{cname}</name>"
        f"<resultIncluded>false</resultIncluded><sequenceNumber>{PROMO_SEQ}</sequenceNumber>{FLAGS}<stepType>ListGroup</stepType></steps>"
        f"<steps><advancedCondition><conditionLogic>1</conditionLogic><criteria><operator>{op}</operator><sequenceNumber>1</sequenceNumber>"
        f"<sourceFieldName>MbQuoteCouponCode</sourceFieldName></criteria></advancedCondition>"
        f"<hasNestedExplainability>false</hasNestedExplainability><label>Filter lines when the quote has a coupon code</label>"
        f"<name>{cname}Filter</name><parentStep>{cname}</parentStep><resultIncluded>false</resultIncluded><sequenceNumber>1</sequenceNumber>{FLAGS}"
        f"<stepType>AdvancedListFilter</stepType></steps>"
        f"<steps><actionType>AssignmentElement</actionType><customElement>"
        + P("section-0-input1", "Parameter", "MbQuoteCouponCode") + P("sectionCount", "Literal", "1")
        + P("sectionJsonString1", "Literal", "{&quot;whereConditions&quot;:[]}") + P("sectionJsonString2", "Literal", cjson)
        + P("section-0-output", "Parameter", "SalesTransactionItemCouponCode__std", out=True)
        + f"</customElement><description>Assignment</description><hasNestedExplainability>false</hasNestedExplainability>"
        f"<label>Line coupon code = quote coupon code</label><name>{cname}Assign</name><parentStep>{cname}</parentStep>"
        f"<resultIncluded>false</resultIncluded><sequenceNumber>2</sequenceNumber>{FLAGS}<stepType>BusinessKnowledgeModel</stepType></steps>"
    )
    s = s[:i] + coupon + s[i:]
    s = s.replace("(quote-level value applied to the lines); promotions.</description>",
                  "(quote-level value applied to the lines); promotions, also from the quote Coupon Code.</description>")
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(s)
print("wrote", OUT, "stage", STAGE)
