/**
 * Mindbody pricing waterfall (spec 12.2, PRC-03..PRC-18, RLP-01, RLP-07, CR-10).
 * One source of truth for the price math, read from the custom metadata tables:
 *
 *   1 List price            price book entry (per location per month)
 *   2 Contract price        master price agreement (RLP-07): replaces list, skips steps 3-5
 *   3 Volume discount       active locations in the whole hierarchy + new ones on the quote (Volume_Discount_Band__mdt)
 *   4 Term discount         contract term in months (Term_Discount__mdt)
 *   5 Frequency discount    billing frequency (Frequency_Discount__mdt)
 *   6 Promotion             promo code, only when its conditions hold (Promotion_Rule__mdt, CR-10)
 *   7 Manual discount       rep-entered percent
 *   8 Floor check           standard net price vs tier floor; combined discount vs auto-approve limit (Tier_Pricing_Rule__mdt)
 *
 * Discounts compound; each step is rounded to the cent. A promotion is time-boxed, so the floor and
 * approval checks use the standard net price (after the promo months) [Assumed – otherwise every
 * LAUNCH3 quote would need VP approval].
 */
public with sharing class MindbodyPricing {

    public class PriceRequest {
        public String productCode;
        public Decimal listPrice;
        public Decimal contractPrice;              // step 2, null when no master price agreement covers the product
        public Integer hierarchyLocations = 0;     // RLP-01: Active_Location_Count__c on the root account
        public Integer newLocations = 0;           // locations of this tier being added on the quote
        public Integer termMonths;                 // null or 0 = evergreen
        public String billingFrequency = 'Monthly';
        public String promoCode;
        public Decimal manualDiscountPercent = 0;
        // promotion conditions (CR-10)
        public Boolean paymentsOptedIn = false;
        public Boolean priorSystemIsCompetitor = false;
        public Boolean dataConversionOnQuote = false;
        public Boolean newCustomer = true;
    }

    public class PriceResult {
        public Decimal listPrice;
        public Boolean contractPriceUsed = false;
        public Integer volumeLocations;
        public Decimal volumeDiscountPercent = 0;
        public Decimal termDiscountPercent = 0;
        public Decimal frequencyDiscountPercent = 0;
        public Decimal manualDiscountPercent = 0;
        public Decimal afterVolume;
        public Decimal afterTerm;
        public Decimal afterFrequency;
        public Decimal netPrice;                   // standard price per location per month
        public String promoCode;
        public Boolean promoApplied = false;
        public Decimal promoPrice;                 // price during the promo months
        public Integer promoMonths;
        public Decimal promoDiscountPercent = 0;   // promo price vs standard net
        public Decimal combinedDiscountPercent = 0;
        public Decimal floorPrice;
        public Boolean belowFloor = false;
        public Decimal autoApprovePercent;
        public Boolean needsApproval = false;
        public List<String> approvalReasons = new List<String>();
        public List<String> messages = new List<String>();
    }

    // ------------------------------------------------------------------ public API

    public static PriceResult price(PriceRequest req) {
        PriceResult r = new PriceResult();
        r.listPrice = cents(req.listPrice == null ? 0.0 : req.listPrice);
        Decimal p = r.listPrice;

        if (req.contractPrice != null) {                                         // step 2
            r.contractPriceUsed = true;
            p = cents(req.contractPrice);
            r.afterVolume = p;
            r.afterTerm = p;
            r.afterFrequency = p;
            r.messages.add('Master price agreement price used; volume, term and frequency discounts skipped (RLP-07).');
        } else {
            r.volumeLocations = nz(req.hierarchyLocations) + nz(req.newLocations);   // step 3
            r.volumeDiscountPercent = volumeDiscount(r.volumeLocations);
            p = off(p, r.volumeDiscountPercent);
            r.afterVolume = p;
            r.termDiscountPercent = termDiscount(req.termMonths);                    // step 4
            p = off(p, r.termDiscountPercent);
            r.afterTerm = p;
            r.frequencyDiscountPercent = frequencyDiscount(req.billingFrequency);    // step 5
            p = off(p, r.frequencyDiscountPercent);
            r.afterFrequency = p;
        }

        Decimal promoBase = p;                                                    // step 6
        if (String.isNotBlank(req.promoCode)) {
            r.promoCode = req.promoCode.trim().toUpperCase();
            List<String> blocked = promoProblems(req, r.promoCode);
            if (blocked.isEmpty()) {
                Promotion_Rule__mdt promo = promotion(r.promoCode);
                r.promoApplied = true;
                r.promoMonths = promo.Promo_Months__c == null ? null : promo.Promo_Months__c.intValue();
                promoBase = promo.Promo_Price__c != null
                    ? cents(Math.min(promo.Promo_Price__c, p))
                    : off(p, nz(promo.Promo_Discount_Percent__c));
            } else {
                r.messages.addAll(blocked);
            }
        }

        r.manualDiscountPercent = nz(req.manualDiscountPercent);                  // step 7
        r.netPrice = off(p, r.manualDiscountPercent);
        if (r.promoApplied) {
            r.promoPrice = off(promoBase, r.manualDiscountPercent);
            r.promoDiscountPercent = r.netPrice == 0 ? 0.0
                : ((r.netPrice - r.promoPrice) / r.netPrice * 100).setScale(2, RoundingMode.HALF_UP);
        }

        r.combinedDiscountPercent = r.listPrice == 0 ? 0.0                          // step 8
            : ((r.listPrice - r.netPrice) / r.listPrice * 100).setScale(2, RoundingMode.HALF_UP);
        Tier_Pricing_Rule__mdt tier = tierRule(req.productCode);
        if (tier != null) {
            r.floorPrice = tier.Floor_Price__c;
            r.autoApprovePercent = tier.Auto_Approve_Percent__c;
            if (r.floorPrice != null && r.netPrice < r.floorPrice) {
                r.belowFloor = true;
                r.approvalReasons.add('Net price ' + r.netPrice + ' is below the ' + req.productCode + ' floor ' + r.floorPrice
                    + ' – VP Sales then Finance (PRC-18)');
            } else if (r.autoApprovePercent == null) {
                r.approvalReasons.add(req.productCode + ' is always approved by the deal desk');
            } else if (r.combinedDiscountPercent > r.autoApprovePercent) {
                r.approvalReasons.add('Combined discount ' + r.combinedDiscountPercent + '% is above the '
                    + r.autoApprovePercent + '% auto-approve limit – sales manager');
            }
        }
        r.needsApproval = !r.approvalReasons.isEmpty();
        return r;
    }

    /** CR-10: why a promotion cannot be applied (empty = it can). */
    public static List<String> promoProblems(PriceRequest req, String code) {
        List<String> out = new List<String>();
        Promotion_Rule__mdt promo = promotion(code);
        if (promo == null) {
            out.add('Promo code ' + code + ' does not exist.');
            return out;
        }
        Set<String> eligible = new Set<String>();
        for (String s : (promo.Eligible_Products__c == null ? '' : promo.Eligible_Products__c).split(';')) {
            if (String.isNotBlank(s)) {
                eligible.add(s.trim());
            }
        }
        if (!eligible.isEmpty() && !eligible.contains(req.productCode)) {
            out.add(code + ' does not apply to ' + req.productCode + ' (only ' + promo.Eligible_Products__c + ').');
        }
        if (promo.Min_Term_Months__c != null && nz(req.termMonths) < promo.Min_Term_Months__c) {
            out.add(code + ' needs a term of at least ' + promo.Min_Term_Months__c.intValue() + ' months.');
        }
        if (promo.Requires_Payments__c && req.paymentsOptedIn != true) {
            out.add(code + ' needs Mindbody Payments opted in (PRC-08).');
        }
        if (promo.Requires_Competitor__c && req.priorSystemIsCompetitor != true) {
            out.add(code + ' needs the prior system to be a competitor.');
        }
        if (promo.Requires_Data_Conversion__c && req.dataConversionOnQuote != true) {
            out.add(code + ' needs Custom data conversion (MB-DCV) on the quote.');
        }
        if (promo.New_Logos_Only__c && req.newCustomer != true) {
            out.add(code + ' is for new customers only.');
        }
        if (promo.Existing_Customers_Only__c && req.newCustomer == true) {
            out.add(code + ' is for existing customers adding locations only.');
        }
        return out;
    }

    // ------------------------------------------------------------------ tables (custom metadata)

    public static Decimal volumeDiscount(Integer locations) {
        Integer n = nz(locations);
        for (Volume_Discount_Band__mdt b : Volume_Discount_Band__mdt.getAll().values()) {
            Boolean aboveMin = b.Min_Locations__c == null || n >= b.Min_Locations__c;
            Boolean belowMax = b.Max_Locations__c == null || n <= b.Max_Locations__c;
            if (aboveMin && belowMax) {
                return nz(b.Discount_Percent__c);
            }
        }
        return 0;
    }

    public static Decimal termDiscount(Integer termMonths) {
        Integer months = nz(termMonths);
        Decimal best = 0;
        Decimal bestMonths = -1;
        // the longest configured term not longer than the contract term
        for (Term_Discount__mdt t : Term_Discount__mdt.getAll().values()) {
            Decimal m = t.Term_Months__c == null ? 0.0 : t.Term_Months__c;
            if (m <= months && m > bestMonths) {
                bestMonths = m;
                best = nz(t.Discount_Percent__c);
            }
        }
        return best;
    }

    public static Decimal frequencyDiscount(String frequency) {
        if (String.isBlank(frequency)) {
            return 0;
        }
        for (Frequency_Discount__mdt f : Frequency_Discount__mdt.getAll().values()) {
            if (f.Frequency__c != null && f.Frequency__c.equalsIgnoreCase(frequency.trim())) {
                return nz(f.Discount_Percent__c);
            }
        }
        return 0;
    }

    public static Tier_Pricing_Rule__mdt tierRule(String productCode) {
        for (Tier_Pricing_Rule__mdt t : Tier_Pricing_Rule__mdt.getAll().values()) {
            if (t.Product_Code__c == productCode) {
                return t;
            }
        }
        return null;
    }

    public static Promotion_Rule__mdt promotion(String code) {
        return String.isBlank(code) ? null : Promotion_Rule__mdt.getInstance(code.trim().toUpperCase());
    }

    // ------------------------------------------------------------------ helpers

    static Decimal off(Decimal price, Decimal percent) {
        return cents(price * (1 - nz(percent) / 100));
    }

    static Decimal cents(Decimal d) {
        return d.setScale(2, RoundingMode.HALF_UP);
    }

    static Decimal nz(Decimal d) {
        return d == null ? 0.0 : d;
    }

    static Integer nz(Integer i) {
        return i == null ? 0 : i;
    }
}
