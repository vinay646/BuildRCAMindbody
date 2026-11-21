// CHANGES the org: adds the running user to the MB approver groups
Id me = UserInfo.getUserId();
List<GroupMember> gm = new List<GroupMember>();
Set<Id> have = new Set<Id>();
for (GroupMember m : [SELECT GroupId FROM GroupMember WHERE UserOrGroupId = :me]) have.add(m.GroupId);
for (Group g : [SELECT Id, DeveloperName FROM Group WHERE DeveloperName IN ('MB_Sales_Manager','MB_Deal_Desk','MB_VP_Sales','MB_Finance')]) if (!have.contains(g.Id)) gm.add(new GroupMember(GroupId = g.Id, UserOrGroupId = me));
insert gm;
System.debug(LoggingLevel.ERROR, 'groups joined: ' + gm.size());
