#!/usr/bin/env python3
"""Version 4 of RLM_DefaultPricingProcedure = version 3 + an "Apply promotions" List Group (Salesforce article
"Configure Your Pricing Procedure for Promotions in Revenue Cloud"), placed after the Mindbody volume / term / billing
frequency discounts and before manual discounts (spec 12.2 waterfall: step 6 Promotion, step 7 Manual discount).
The Promotion Execution element itself is added inside the group in the builder (rule library RLM_RuleLibrary,
scope Line). Version 4 was created in the builder (Save As New Version); this deploys onto that draft.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "deploy/pricing-v3/main/default/expressionSetDefinition/RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml"
OUT = ROOT / "deploy/pricing-v4/main/default/expressionSetDefinition/RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml"
V3 = "RLM_DefaultPricingProcedure_RLM_Revenue_Management_Default_Pricing_Procedure_V30"
V4 = "RLM_DefaultPricingProcedure_RLM_Revenue_Management_Default_Pricing_Procedure_V40"
PROMO_SEQ = 21  # before "Apply manual discounts to lines without derived pricing"
FLAGS = ("<shouldExposExecPathMsgOnly>true</shouldExposExecPathMsgOnly><shouldExposeConditionDetails>false</shouldExposeConditionDetails>"
         "<shouldShowExplExternally>false</shouldShowExplExternally>")
GROUP = (
    f"<steps><hasNestedExplainability>false</hasNestedExplainability><label>Apply promotions</label>"
    f"<name>Applypromotions</name><resultIncluded>false</resultIncluded><sequenceNumber>{PROMO_SEQ}</sequenceNumber>{FLAGS}"
    f"<stepType>ListGroup</stepType></steps>"
    f"<steps><advancedCondition><conditionLogic>(1 OR 2) AND 3</conditionLogic>"
    f"<criteria><operator>IsNull</operator><sequenceNumber>1</sequenceNumber><sourceFieldName>IsContracted</sourceFieldName></criteria>"
    f"<criteria><operator>Equals</operator><sequenceNumber>2</sequenceNumber><sourceFieldName>IsContracted</sourceFieldName><value>false</value><valueType>Literal</valueType></criteria>"
    f"<criteria><operator>NotEquals</operator><sequenceNumber>3</sequenceNumber><sourceFieldName>ItemPricingSource</sourceFieldName><value>&apos;LastTransaction&apos;</value><valueType>Literal</valueType></criteria>"
    f"</advancedCondition><hasNestedExplainability>false</hasNestedExplainability><label>Filter lines without contract or last-trxn pricing</label>"
    f"<name>Filterlinesforpromotions</name><parentStep>Applypromotions</parentStep><resultIncluded>false</resultIncluded>"
    f"<sequenceNumber>1</sequenceNumber>{FLAGS}<stepType>AdvancedListFilter</stepType></steps>"
    f"<steps><actionType>PromotionExecution</actionType><customElement>"
    + "".join(f"<parameters><input>true</input><name>{n}</name><output>false</output><type>{t}</type><value>{v}</value></parameters>"
              for n, t, v in [("RuleLibrary", "Literal", "RLM_RuleLibrary"), ("PromotionScope", "Literal", "Line"),
                              ("Subtotal", "Parameter", "ItemNetTotalPrice"), ("Quantity", "Parameter", "LineItemQuantity"),
                              ("InputUnitPrice", "Parameter", "NetUnitPrice"), ("HideWaterfall", "Literal", "false"),
                              ("sectionCount", "Literal", "0"), ("selectedFunction", "Literal", "Get"), ("IsRealTime", "Literal", "false")])
    + "<parameters><input>false</input><name>NetUnitPrice</name><output>true</output><type>Parameter</type><value>NetUnitPrice</value></parameters>"
    + "<parameters><input>false</input><name>Subtotal</name><output>true</output><type>Parameter</type><value>ItemNetTotalPrice</value></parameters>"
    + f"</customElement><description>Promotion Execution</description><hasNestedExplainability>false</hasNestedExplainability>"
    f"<label>Apply promotions from the rule library</label><name>Applypromotionsfromtherulelibrary</name><parentStep>Applypromotions</parentStep>"
    f"<resultIncluded>false</resultIncluded><sequenceNumber>2</sequenceNumber>{FLAGS}<stepType>BusinessKnowledgeModel</stepType></steps>")


def main():
    s = SRC.read_text()
    v = re.search(r"<versions>.*?</versions>", s, re.S).group(0)
    v = v.replace(f"<fullName>{V3}</fullName>", f"<fullName>{V4}</fullName>", 1)
    v = v.replace("<label>RLM Revenue Management Default Pricing Procedure V3</label>",
                  "<label>RLM Revenue Management Default Pricing Procedure V4</label>", 1)
    v = re.sub(r"<rank>\d+</rank>", "<rank>4</rank>", v, 1)
    v = v.replace("<versionNumber>3</versionNumber>", "<versionNumber>4</versionNumber>", 1)
    v = re.sub(r"<status>\w+</status>", "<status>Draft</status>", v, 1)

    def shift(m):
        st = m.group(0)
        outer = re.sub(r"<customElement>.*?</customElement>", "", st, flags=re.S)
        if "<parentStep>" in outer:
            return st
        seq = int(re.search(r"<sequenceNumber>(\d+)</sequenceNumber>", outer).group(1))
        if seq < PROMO_SEQ:
            return st
        tail = st.rfind("<sequenceNumber>")
        return st[:tail] + re.sub(r"<sequenceNumber>\d+</sequenceNumber>", f"<sequenceNumber>{seq + 1}</sequenceNumber>", st[tail:], count=1)
    v = re.sub(r"<steps>.*?</steps>", shift, v, flags=re.S)
    first = v.index("<steps>")
    v = v[:first] + GROUP + v[first:]
    out = s[:s.index("<versions>")] + v + s[s.rindex("</versions>") + len("</versions>"):]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(out)
    print(OUT.relative_to(ROOT), v.count("<steps>"), "steps")


if __name__ == "__main__":
    main()
