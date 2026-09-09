App UI copy lives in `Apps/Localizable.xcstrings`. policycheck fails if a SwiftUI
literal is missing from the English catalog or English completeness drops below
95%. Simulator UI tests also audit disclosure and controls under doubled strings
and forced RTL.
