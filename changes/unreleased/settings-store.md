Every app preference key now lives in one typed place (`SettingKey` and
`SettingsStore`); the stored keys are unchanged, so existing settings carry over.
policycheck rejects raw preference keys anywhere else in the app (#42, part 1).
