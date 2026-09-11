SEC-14: require a typed confirmation phrase before enabling a destination whose
resolved address is public. Private, loopback and link-local destinations retain
the existing one-tap identity confirmation. The public-address gate uses the
probe's resolved address, with a literal-IP fallback for unencrypted transports,
and has an XCUITest proving enable remains disabled until the phrase is entered.
