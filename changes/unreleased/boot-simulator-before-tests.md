Boot the UI-test simulator and wait for it before xcodebuild runs. Left to
boot lazily it raced the first app launch, and the shard failed with "Timed
out while launching application via Xcode" for a reason that had nothing to
do with the app.
