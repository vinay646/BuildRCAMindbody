#!/usr/bin/env python3
"""Version 5 of RLM_DefaultPricingProcedure = version 4 + a floor price lookup (PRC-18).

Standard List Price element (the same one the procedure uses for the cost book) reads the "Mindbody Floor Prices" price
book through the standard Price Book Entries V2 lookup, in the quote currency and selling model, and writes the tier floor
to the line tag MbFloorPrice (mapped to Quote Line Item › Floor Price). It does not change any price; Quote Line Item ›
Below Floor compares Net Unit Price with it and drives the VP Sales → Finance approval (phase 5).
Placed after manual discounts, before the price-revision / proration steps. Version 5 is created in the builder
(Save As New Version from version 4); this deploys onto that draft.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "deploy/pricing-v4/main/default/expressionSetDefinition/RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml"
OUT = ROOT / "deploy/pricing-v5/main/default/expressionSetDefinition/RLM_DefaultPricingProcedure.expressionSetDefinition-meta.xml"
V4 = "RLM_DefaultPricingProcedure_RLM_Revenue_Management_Default_Pricing_Procedure_V40"
V5 = "RLM_DefaultPricingProcedure_RLM_Revenue_Management_Default_Pricing_Procedure_V50"
FLOOR_BOOK_ID = "01shm000001QRonAAG"  # Pricebook2 "Mindbody Floor Prices"
FLOOR_SEQ = 24  # after "Apply amount-based and percentage-based discounts" (23)
FLAGS = ("<shouldExposExecPathMsgOnly>true</shouldExposExecPathMsgOnly><shouldExposeConditionDetails>false</shouldExposeConditionDetails>"
         "<shouldShowExplExternally>false</shouldShowExplExternally>")
P = lambda n, t, v, out=False: (f"<parameters><input>{'false' if out else 'true'}</input><name>{n}</name><output>{'true' if out else 'false'}</output>"
                                f"<type>{t}</type><value>{v}</value></parameters>")
STEP = ("<steps><actionType>ListPrice</actionType><customElement>"
        + P("Product2Id", "Parameter", "Product") + P("Pricebook2Id", "Literal", FLOOR_BOOK_ID)
        + P("ProductSellingModelId", "Parameter", "ProductSellingModel") + P("Quantity", "Parameter", "LineItemQuantity")
        + P("ListPriceField", "Parameter", "Constant_UnitPrice_Price_Book_Entry_Decision_Table_v2_LP")
        + P("LookUpName", "Literal", "Price Book Entries V2") + P("LookUpId", "Literal", "0lDhm00000017XREAY")
        + P("LookUpApiName", "Literal", "Price_Book_Entry_Decision_Table_v2") + P("IsContractEnabled", "Literal", "false")
        + P("HideWaterfall", "Literal", "true") + P("IsOutputResolutionEnabled", "Literal", "false")
        + P("sectionCount", "Literal", "0") + P("selectedFunction", "Literal", "Get") + P("IsRealTime", "Literal", "false")
        + P("ListPrice", "Parameter", "MbFloorPrice", out=True)
        + "</customElement><description>List Price</description><hasNestedExplainability>false</hasNestedExplainability>"
        f"<label>Get floor price from the Mindbody Floor Prices price book</label><name>Getfloorpricefromfloorpricebook</name>"
        f"<resultIncluded>false</resultIncluded><sequenceNumber>{FLOOR_SEQ}</sequenceNumber>{FLAGS}<stepType>BusinessKnowledgeModel</stepType></steps>")


def main():
    s = SRC.read_text()
    v = re.search(r"<versions>.*?</versions>", s, re.S).group(0)
    v = v.replace(f"<fullName>{V4}</fullName>", f"<fullName>{V5}</fullName>", 1)
    v = v.replace("<label>RLM Revenue Management Default Pricing Procedure V4</label>",
                  "<label>RLM Revenue Management Default Pricing Procedure V5</label>", 1)
    v = re.sub(r"<rank>\d+</rank>", "<rank>5</rank>", v, count=1)
    v = v.replace("<versionNumber>4</versionNumber>", "<versionNumber>5</versionNumber>", 1)
    v = re.sub(r"<status>\w+</status>", "<status>Draft</status>", v, count=1)
    assert "Getfloorpricefromfloorpricebook" not in v

    def shift(m):
        st = m.group(0)
        outer = re.sub(r"<customElement>.*?</customElement>", "", st, flags=re.S)
        if "<parentStep>" in outer:
            return st
        seq = int(re.search(r"<sequenceNumber>(\d+)</sequenceNumber>", outer).group(1))
        if seq < FLOOR_SEQ:
            return st
        tail = st.rfind("<sequenceNumber>")
        return st[:tail] + re.sub(r"<sequenceNumber>\d+</sequenceNumber>", f"<sequenceNumber>{seq + 1}</sequenceNumber>", st[tail:], count=1)
    v = re.sub(r"<steps>(?:(?!<steps>).)*?</steps>", shift, v, flags=re.S)
    first = v.index("<steps>")
    v = v[:first] + STEP + v[first:]
    out = s[:s.index("<versions>")] + v + s[s.rindex("</versions>") + len("</versions>"):]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(out)
    print(OUT.relative_to(ROOT), v.count("<steps>"), "steps")


if __name__ == "__main__":
    main()
