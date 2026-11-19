List<String> found = new List<String>();
for (String n : new List<String>{ 'ConfigurationExecutionEnum', 'ConfigMethodEnum', 'ConfigurationInput', 'ConfigurationPrefEnum', 'ConfigurationEnum',
    'ConfigurationInputsEnum', 'ConfigurationExecutionPreferenceEnum', 'ConfigurationTypeEnum', 'ConfiguratorEnum', 'ConfigurationModeEnum',
    'ConfigurationOptionEnum', 'ConfigurationInputPreferenceEnum', 'RunConfigurationEnum', 'ConfigPreferenceEnum', 'ConfigurationActionEnum',
    'ConfigurationStrategyEnum', 'ConfigurationExecutionInput', 'ConfigurationPreferenceInputEnum', 'ConfigurationMethod', 'ConfigurationPref',
    'ConfigurationPrefInput', 'ConfigurationPreferencesInput', 'ConfigPrefInput', 'ConfigurationInputType', 'GroupRampActionEnum',
    'SalesTransactionTypeEnum', 'PlaceSalesTransactionInput', 'PlaceSalesTransactionInputRepresentation', 'PlaceSalesTransactionRequestInput',
    'GraphInput', 'RecordInput', 'ResponseError', 'ErrorResponseRepresentation', 'PlaceSalesTransactionErrorResponse', 'StatusEnum',
    'ConfigurationPreferenceEnum', 'ConfigurationInputEnum', 'ConfigurationExecutionMethodEnum', 'ConfigurationRunEnum',
    'ConfigurationEnforcementEnum', 'ConfigurationValidationEnum', 'ValidationPreferenceEnum', 'ConfiguratorPreferenceEnum',
    'ConfigurationRuleEnum', 'ProductConfigurationEnum', 'ConfigurationRunPreferenceEnum', 'ConfigurationPreferenceTypeEnum' }) {
    if (Type.forName('RevSalesTrxn', n) != null) { found.add(n); }
}
System.debug(LoggingLevel.ERROR, 'FOUND RevSalesTrxn: ' + found);
