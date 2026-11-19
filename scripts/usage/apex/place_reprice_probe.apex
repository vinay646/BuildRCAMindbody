// Reprices test quote 00000140 (COUPON-FLOW) through PlaceQuote.PlaceQuoteExecutor: PATCH the quote with no field changes, pricing Force.
Quote qt = [SELECT Id, QuoteNumber FROM Quote WHERE QuoteNumber = '00000140' LIMIT 1];
PlaceQuote.RecordResource rec = new PlaceQuote.RecordResource(Quote.getSObjectType(), 'PATCH', qt.Id);
rec.fieldValues = new Map<String, Object>{ 'Description' => 'apex reprice ' + System.now() };
PlaceQuote.RecordWithReferenceRequest ref = new PlaceQuote.RecordWithReferenceRequest('q1', rec);
PlaceQuote.GraphRequest graph = new PlaceQuote.GraphRequest('reprice', new List<PlaceQuote.RecordWithReferenceRequest>{ ref });
PlaceQuote.ConfigurationOptionsInput opts = new PlaceQuote.ConfigurationOptionsInput();
PlaceQuote.PlaceQuoteResponse r = PlaceQuote.PlaceQuoteExecutor.execute(graph, PlaceQuote.PricingPreferenceEnum.Force,
    PlaceQuote.ConfigurationInputEnum.Skip, opts);
System.debug(LoggingLevel.ERROR, 'RESULT success=' + r.isSuccess + ' quote=' + r.quoteId + ' errors=' + r.responseError);
