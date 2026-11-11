/** RLP-01: queue a recount of active locations when core-tier assets change (LocationCountService). */
trigger AssetTrigger on Asset (after insert, after update, after delete, after undelete) {
    LocationCountService.assetsChanged(Trigger.isDelete ? Trigger.old : Trigger.new);
}
