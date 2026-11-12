#!/usr/bin/env python3
"""Version 3 of RLM_DefaultPricingProcedure (one pricing procedure for the org), built from version 2 in force-app.

Version 2 read two tier bounds from QuoteLineItem formula fields. A new line is priced before it is saved, so those
were empty and every tier matched ("Duplicate entries found while looking up VolumeDiscount"). Version 3 only reads
values that exist before the line is saved – standard elements only:
  * Billing months: four standard ListGroup + AdvancedListFilter + Assignment groups (the pattern the procedure uses
    for evergreen term counts) set the transient line tag MbBillingMonths from the standard ItemBillingFrequency.
  * Volume tier bound: the quote header tag MbHierarchyLocationCount (active locations in the account hierarchy).
  * Contract term tier bound: the quote header tag MbQuoteTermMonths (Quote Term (Months)).
Versions 1 and 2 stay unchanged (an active version cannot be updated by deploy).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
F = ROOT / "force-app/main/default/expressionSetDefinition/RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml"
VOLUME_GROUP_SEQ = 16  # "Apply volume-based discounts to lines without contract or last-trxn pricing"
MONTHS = [("Monthly", 1), ("Quarterly", 3), ("Semi-Annual", 6), ("Annual", 12)]


def bound(step_xml, old, new):
    out, n = re.subn(rf"(<name>(?:LowerBound|UpperBound)</name><output>false</output><type>Parameter</type><value>){old}(</value>)",
                     rf"\g<1>{new}\g<2>", step_xml)
    if n != 2:
        sys.exit(f"bounds {old}: expected 2, found {n}")
    return out


def group(freq, months, seq):
    key = re.sub(r"[^A-Za-z]", "", freq)
    g = f"MindbodyBillingMonths{key}"
    q = "&quot;"
    js = ("{" + q + "whereConditions" + q + ":[{" + q + "field" + q + ":{" + q + "dataType" + q + ":" + q + "Numeric" + q + ","
          + q + "name" + q + ":" + q + "section-0-input1" + q + "," + q + "value" + q + ":" + q + f"MbBillingMonths{months}Constant" + q + ","
          + q + "allowCompatibleDataTypes" + q + ":true}," + q + "value" + q + ":{" + q + "dataType" + q + ":" + q + "Numeric" + q + ","
          + q + "name" + q + ":" + q + "section-0-output" + q + "," + q + "value" + q + ":" + q + "MbBillingMonths" + q + ","
          + q + "allowCompatibleDataTypes" + q + ":true}}]}")
    flags = ("<shouldExposExecPathMsgOnly>true</shouldExposExecPathMsgOnly><shouldExposeConditionDetails>false</shouldExposeConditionDetails>"
             "<shouldShowExplExternally>false</shouldShowExplExternally>")
    return (
        f"<steps><hasNestedExplainability>false</hasNestedExplainability><label>Mindbody billing months – {freq}</label>"
        f"<name>{g}</name><resultIncluded>false</resultIncluded><sequenceNumber>{seq}</sequenceNumber>{flags}<stepType>ListGroup</stepType></steps>"
        f"<steps><advancedCondition><conditionLogic>1</conditionLogic><criteria><operator>Equals</operator><sequenceNumber>1</sequenceNumber>"
        f"<sourceFieldName>ItemBillingFrequency</sourceFieldName><value>'{freq}'</value><valueType>Literal</valueType></criteria></advancedCondition>"
        f"<hasNestedExplainability>false</hasNestedExplainability><label>Filter {freq} lines</label><name>{g}Filter</name>"
        f"<parentStep>{g}</parentStep><resultIncluded>false</resultIncluded><sequenceNumber>1</sequenceNumber>{flags}<stepType>AdvancedListFilter</stepType></steps>"
        f"<steps><actionType>AssignmentElement</actionType><customElement>"
        f"<parameters><input>true</input><name>section-0-input1</name><output>false</output><type>Parameter</type><value>MbBillingMonths{months}Constant</value></parameters>"
        f"<parameters><input>true</input><name>sectionCount</name><output>false</output><type>Literal</type><value>1</value></parameters>"
        f"<parameters><input>true</input><name>sectionJsonString1</name><output>false</output><type>Literal</type><value>{{{q}whereConditions{q}:[]}}</value></parameters>"
        f"<parameters><input>true</input><name>sectionJsonString2</name><output>false</output><type>Literal</type><value>{js}</value></parameters>"
        f"<parameters><input>false</input><name>section-0-output</name><output>true</output><type>Parameter</type><value>MbBillingMonths</value></parameters>"
        f"</customElement><description>Assignment</description><hasNestedExplainability>false</hasNestedExplainability>"
        f"<label>Assign {months} billing months</label><name>{g}Assign</name><parentStep>{g}</parentStep><resultIncluded>false</resultIncluded>"
        f"<sequenceNumber>2</sequenceNumber>{flags}<stepType>BusinessKnowledgeModel</stepType></steps>")


def main():
    s = F.read_text()
    if "RLM_DefaultPricingProcedure_RLM_Revenue_Management_Default_Pricing_Procedure_V30" in s:
        sys.exit("version 3 already in the file")
    start = s.index("<versions><fullName>RLM_DefaultPricingProcedure_V2</fullName>")
    end = s.index("</versions>", start) + len("</versions>")
    v = s[start:end]
    v = v.replace("<fullName>RLM_DefaultPricingProcedure_V2</fullName>", "<fullName>RLM_DefaultPricingProcedure_RLM_Revenue_Management_Default_Pricing_Procedure_V30</fullName>", 1)
    v = v.replace("<rank>2</rank>", "<rank>3</rank>", 1).replace("<versionNumber>2</versionNumber>", "<versionNumber>3</versionNumber>", 1)
    # tier bounds
    steps = re.findall(r"<steps>.*?</steps>", v)
    for st in steps:
        if "<value>MbHierarchyVolumePASId</value>" in st:
            v = v.replace(st, bound(st, "MbVolumeLocationCount", "MbHierarchyLocationCount"), 1)
        elif "<value>MbContractTermPASId</value>" in st:
            v = v.replace(st, bound(st, "ItemSubscriptionTerm", "MbQuoteTermMonths"), 1)
        elif "<value>MbBillingFrequencyPASId</value>" in st:
            v = v.replace(st, bound(st, "MbBillingPeriodMonths", "MbBillingMonths"), 1)
    # shift top-level steps from the volume group on, then insert the four billing-month groups before it
    def shift(m):
        st = m.group(0)
        outer = re.sub(r"<customElement>.*?</customElement>", "", st)
        if "<parentStep>" in outer:
            return st
        seq = int(re.search(r"<sequenceNumber>(\d+)</sequenceNumber>", outer).group(1))
        if seq < VOLUME_GROUP_SEQ:
            return st
        tail = st.rfind("<sequenceNumber>")
        return st[:tail] + re.sub(r"<sequenceNumber>\d+</sequenceNumber>", f"<sequenceNumber>{seq + len(MONTHS)}</sequenceNumber>", st[tail:], 1)
    v = re.sub(r"<steps>.*?</steps>", shift, v)
    first = re.search(r"<steps>", v).start()
    v = v[:first] + "".join(group(f, m, VOLUME_GROUP_SEQ + i) for i, (f, m) in enumerate(MONTHS)) + v[first:]
    consts = "".join(
        f"<variables><collection>false</collection><dataType>Numeric</dataType><decimalPlaces>0</decimalPlaces>"
        f"<description>Months per billing period: {f}</description><input>false</input><name>MbBillingMonths{m}Constant</name>"
        f"<output>false</output><type>Constant</type><value>{m}</value></variables>" for f, m in MONTHS)
    i = v.index("<variables>")
    v = v[:i] + consts + v[i:]
    v = v.replace("<description>Revenue Management Default Pricing Procedure</description>",
                  "<description>Revenue Management Default Pricing Procedure + Mindbody volume (hierarchy locations), contract term "
                  "(quote term) and billing frequency (billing months) discounts – v3 reads only values present before a line is saved.</description>", 1)
    s = s[:end] + v + s[end:]
    F.write_text(s)
    print("version 3 added:", len(re.findall(r"<steps>", v)), "steps")


if __name__ == "__main__":
    main()
