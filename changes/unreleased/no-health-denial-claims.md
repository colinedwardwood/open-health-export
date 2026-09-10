`policycheck` now fails the build on any user-facing string that claims a Health read was
denied (R-60). Apple makes a denied read indistinguishable from absent data, so the claim
would be a guess presented as fact. Copy may still name the ambiguity — "Apple does not
tell us whether you allowed or denied a type" passes — and positively detectable denials
such as Local Network keep their own distinct wording.

Zero-result copy now also hands over the route to check: Health, Sharing, then Apps.
