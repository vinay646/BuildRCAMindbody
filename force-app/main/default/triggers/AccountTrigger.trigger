/** Account hierarchy: root account and resolved payer (AccountHierarchyService). */
trigger AccountTrigger on Account (after insert, after update) {
    if (Trigger.isInsert) {
        AccountHierarchyService.afterInsert(Trigger.new);
    } else {
        AccountHierarchyService.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}
