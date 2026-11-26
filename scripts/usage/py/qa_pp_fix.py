"""QA: in the given version, the 'Mindbody line term from quote' filter applies to every term-defined line (not only blank term)."""
import sys,re,os
src,out=sys.argv[1],sys.argv[2]; VER=os.environ.get('VER','4')
x=open(src).read()
vers=re.findall(r'<versions>.*?</versions>', x, re.S)
v=[t for t in vers if f'<versionNumber>{VER}</versionNumber>' in t][0]
assert 'MindbodyLineTermFromQuote' in v, 'step missing'
old=re.search(r'<advancedCondition>(?:(?!</advancedCondition>).)*?</advancedCondition>(?=(?:(?!<steps>).)*?<name>MindbodyLineTermFromQuoteFilter</name>)', v, re.S)
newc=("<advancedCondition><conditionLogic>1</conditionLogic><criteria><operator>Equals</operator><sequenceNumber>1</sequenceNumber>"
      "<sourceFieldName>SellingModelType</sourceFieldName><value>&apos;TermDefined&apos;</value><valueType>Literal</valueType></criteria></advancedCondition>")
v2=v[:old.start()]+newc+v[old.end():]
v2=v2.replace('<label>Filter term-defined lines without a subscription term</label>','<label>Filter term-defined lines</label>')
v2=v2.replace('<status>Active</status>','<status>Draft</status>')
first=x.index(vers[0]); last=x.rindex(vers[-1])+len(vers[-1])
open(out,'w').write(x[:first]+v2+x[last:]); print('BUILT fix on version', VER)
