Declare NSAllowsLocalNetworking as the only App Transport Security exception
on the iOS exporter. policycheck fails if NSAllowsArbitraryLoads* appears in
any Apps Info.plist (R-35 / SEC-19).
