/**
 * MR-103 / spec CR-10: eligibility rules for the quote Coupon Code.
 * Called by the MB Quote Coupon Code flow before the coupon is applied; a non-blank message
 * makes the flow stop the save with that message on the Coupon Code field.
 */
public with sharing class MbCouponRules {

    public class Request {
        @InvocableVariable(label='Quote Id' required=true)
        public Id quoteId;
        @InvocableVariable(label='Coupon code')
        public String couponCode;
    }

    public class Result {
        @InvocableVariable(label='Rejection message (blank = allowed)')
        public String message;
    }

    @InvocableMethod(label='MB Check coupon rules' description='Returns why the quote does not qualify for the coupon, or blank when it does.')
    public static List<Result> check(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request r : requests) {
            Result res = new Result();
            res.message = check(r.quoteId, r.couponCode);
            results.add(res);
        }
        return results;
    }

    public static String check(Id quoteId, String couponCode) {
        String code = couponCode == null ? '' : couponCode.trim().toUpperCase();
        if (String.isBlank(code) || quoteId == null) {
            return null;
        }
        Quote q = [SELECT Id, AccountId, RLM_TermMonths__c, Prior_system__c, Opportunity.Prior_System__c FROM Quote WHERE Id = :quoteId];
        Set<String> codes = new Set<String>();
        for (QuoteLineItem l : [SELECT Product2.ProductCode FROM QuoteLineItem WHERE QuoteId = :quoteId]) {
            codes.add(l.Product2.ProductCode);
        }
        Decimal term = q.RLM_TermMonths__c == null ? 0 : q.RLM_TermMonths__c;
        String prior = q.Opportunity == null ? null : q.Opportunity.Prior_System__c;
        if (String.isBlank(prior)) { prior = q.Prior_system__c; }
        List<String> reasons = new List<String>();

        if (code == 'LAUNCH3') {
            if (!codes.contains('MB-STR')) reasons.add('the quote must include the Starter plan');
            if (term < 12) reasons.add('the term must be at least 12 months');
            if (!codes.contains('MB-PAY')) reasons.add('the quote must include Mindbody Payments');
            if (isExistingCustomer(q.AccountId)) reasons.add('it is for new customers only');
        } else if (code == 'SWITCH50') {
            if (!codes.contains('MB-ACC') && !codes.contains('MB-ULT')) reasons.add('the quote must include the Accelerate or Ultimate plan');
            if (String.isBlank(prior) || prior == 'None') reasons.add('the opportunity must name the competitor in Prior System');
            if (term < 24) reasons.add('the term must be at least 24 months');
            if (!codes.contains('MB-DCV')) reasons.add('the quote must include Data Conversion');
        } else if (code == 'GROW2') {
            if (!isExistingCustomer(q.AccountId)) reasons.add('it is for existing customers adding a location');
        }
        return reasons.isEmpty() ? null : 'Coupon ' + code + ' can\'t be used: ' + String.join(reasons, '; ') + '.';
    }

    /** Existing customer: the account has assets (QA has no account location count field). */
    public static Boolean isExistingCustomer(Id accountId) {
        if (accountId == null) {
            return false;
        }
        return [SELECT COUNT() FROM Asset WHERE AccountId = :accountId] > 0;
    }
}
