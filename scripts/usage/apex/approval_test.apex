// CHANGES the org: adds the running user to the MB approver groups; sets Discount 30% on test quote 00000231 (Accelerate) to trigger the over-limit rule.
Id me = UserInfo.getUserId();
List<GroupMember> gm = new List<GroupMember>();
Set<Id> have = new Set<Id>();
for (GroupMember m : [SELECT GroupId FROM GroupMember WHERE UserOrGroupId = :me]) have.add(m.GroupId);
for (Group g : [SELECT Id, DeveloperName FROM Group WHERE DeveloperName IN ('MB_Sales_Manager','MB_Deal_Desk','MB_VP_Sales','MB_Finance')]) if (!have.contains(g.Id)) gm.add(new GroupMember(GroupId = g.Id, UserOrGroupId = me));
insert gm;
System.debug(LoggingLevel.ERROR, 'groups joined: ' + gm.size());
QuoteLineItem l = [SELECT Id FROM QuoteLineItem WHERE Quote.QuoteNumber = '00000231' AND Product2.ProductCode = 'MB-ACC' LIMIT 1];
l.Discount = 30; update l;
List<String> qns = new List<String>{ '00000231', '00000263', '00000040' };
for (Quote q : [SELECT Id, QuoteNumber FROM Quote WHERE Id IN (SELECT QuoteId FROM QuoteLineItem WHERE Product2.ProductCode = 'MB-ENT') ORDER BY CreatedDate DESC LIMIT 1]) qns.add(q.QuoteNumber);
for (Quote q : [SELECT Id, QuoteNumber FROM Quote WHERE QuoteNumber IN :qns]) {
    Flow.Interview fi = Flow.Interview.createInterview('RLM_Quote_Approval_Data', new Map<String, Object>{ 'QuoteId' => q.Id });
    fi.start();
    QuoteLineItem p = [SELECT Product2.ProductCode, Discount, MB_Auto_Approve_Limit__c, NetUnitPrice, MB_Floor_Price__c, MB_Below_Floor__c FROM QuoteLineItem WHERE QuoteId = :q.Id AND Product2.ProductCode IN ('MB-STR','MB-ACC','MB-ULT','MB-ENT') LIMIT 1];
    System.debug(LoggingLevel.ERROR, q.QuoteNumber + ' ' + p.Product2.ProductCode + ' disc ' + p.Discount + '% limit ' + p.MB_Auto_Approve_Limit__c + ' net ' + p.NetUnitPrice + ' floor ' + p.MB_Floor_Price__c
        + ' => discount approval ' + fi.getVariableValue('NeedsDiscountApproval') + ', enterprise ' + fi.getVariableValue('HasEnterprise') + ', below floor ' + fi.getVariableValue('BelowFloor'));
}
