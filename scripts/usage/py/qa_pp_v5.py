"""QA: build RLM_DefaultPricingProcedure version N+1 = active version + a first step that fills a blank line Subscription Term from the quote Term (Months)."""
import sys,re,datetime
src,out=sys.argv[1],sys.argv[2]
x=open(src).read()
vers=re.findall(r'<versions>.*?</versions>', x, re.S)
act=[v for v in vers if '<status>Active</status>' in v][0]
n=int(re.search(r'<versionNumber>(\d+)</versionNumber>', act).group(1)); m=max(int(re.search(r'<versionNumber>(\d+)</versionNumber>', v).group(1)) for v in vers)+1
v=act.replace('<status>Active</status>','<status>Draft</status>').replace(f'<versionNumber>{n}</versionNumber>',f'<versionNumber>{m}</versionNumber>')
v=re.sub(r'(<fullName>[^<]*_V)\d+0(</fullName>)', lambda k: f'{k.group(1)}{m}0{k.group(2)}', v)
v=re.sub(r'<rank>\d+</rank>', f'<rank>{m}</rank>', v)
v=re.sub(r'<startDate>[^<]*</startDate>', f'<startDate>{datetime.date.today()}T00:00:00.000Z</startDate>', v, count=1)
v=re.sub(r'(<label>[^<]*?)V\d+(</label>)', lambda k: f'{k.group(1)}V{m}{k.group(2)}', v, count=1)
def shift(mm):
    b=mm.group(0)
    if '<parentStep>' in b: return b
    k=int(re.search(r'<sequenceNumber>(\d+)</sequenceNumber>', b).group(1))
    return b.replace(f'<sequenceNumber>{k}</sequenceNumber>', f'<sequenceNumber>{k+1}</sequenceNumber>',1)
v=re.sub(r'<steps>(?:(?!<steps>).)*?</steps>', shift, v, flags=re.S)
FL=('<shouldExposExecPathMsgOnly>true</shouldExposExecPathMsgOnly><shouldExposeConditionDetails>false</shouldExposeConditionDetails>'
    '<shouldShowExplExternally>false</shouldShowExplExternally>')
def P(nm,t,val,o=False): return f"<parameters><input>{'false' if o else 'true'}</input><name>{nm}</name><output>{'true' if o else 'false'}</output><type>{t}</type><value>{val}</value></parameters>"
DT=sys.argv[3] if len(sys.argv)>3 else 'Numeric'
js=('{&quot;whereConditions&quot;:[{&quot;field&quot;:{&quot;dataType&quot;:&quot;'+DT+'&quot;,&quot;name&quot;:&quot;section-0-input1&quot;,'
    '&quot;value&quot;:&quot;SalesTransaction_RLMTermMonths__c&quot;,&quot;allowCompatibleDataTypes&quot;:true},&quot;value&quot;:{&quot;dataType&quot;:'
    '&quot;'+DT+'&quot;,&quot;name&quot;:&quot;section-0-output&quot;,&quot;value&quot;:&quot;ItemSubscriptionTerm&quot;,&quot;allowCompatibleDataTypes&quot;:true}}]}')
G='MindbodyLineTermFromQuote'
new=(f"<steps><hasNestedExplainability>false</hasNestedExplainability><label>Mindbody line term from quote</label><name>{G}</name>"
 f"<resultIncluded>false</resultIncluded><sequenceNumber>1</sequenceNumber>{FL}<stepType>ListGroup</stepType></steps>"
 f"<steps><advancedCondition><conditionLogic>1 AND 2</conditionLogic>"
 f"<criteria><operator>IsNull</operator><sequenceNumber>1</sequenceNumber><sourceFieldName>ItemSubscriptionTerm</sourceFieldName></criteria>"
 f"<criteria><operator>Equals</operator><sequenceNumber>2</sequenceNumber><sourceFieldName>SellingModelType</sourceFieldName><value>&apos;TermDefined&apos;</value><valueType>Literal</valueType></criteria>"
 f"</advancedCondition><hasNestedExplainability>false</hasNestedExplainability><label>Filter term-defined lines without a subscription term</label>"
 f"<name>{G}Filter</name><parentStep>{G}</parentStep><resultIncluded>false</resultIncluded><sequenceNumber>1</sequenceNumber>{FL}<stepType>AdvancedListFilter</stepType></steps>"
 f"<steps><actionType>AssignmentElement</actionType><customElement>"
 + P('section-0-input1','Parameter','SalesTransaction_RLMTermMonths__c') + P('sectionCount','Literal','1')
 + P('sectionJsonString1','Literal','{&quot;whereConditions&quot;:[]}') + P('sectionJsonString2','Literal',js)
 + P('section-0-output','Parameter','ItemSubscriptionTerm',True)
 + f"</customElement><description>Assignment</description><hasNestedExplainability>false</hasNestedExplainability>"
 f"<label>Line subscription term = quote Term (Months)</label><name>{G}Assign</name><parentStep>{G}</parentStep>"
 f"<resultIncluded>false</resultIncluded><sequenceNumber>2</sequenceNumber>{FL}<stepType>BusinessKnowledgeModel</stepType></steps>")
i=v.index('<steps>'); v=v[:i]+new+v[i:]
# keep only the new version in the file (deploy adds it as Draft; existing versions untouched)
first=x.index(vers[0]); last=x.rindex(vers[-1])+len(vers[-1])
y=x[:first]+v+x[last:]
open(out,'w').write(y)
print('BUILT version', m, 'from active', n, 'dataType', DT)
