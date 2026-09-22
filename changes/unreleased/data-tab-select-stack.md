Selecting types uses the same full-width button style as Status, stacked
under Select, so Invert/Clear are actually tappable. Hosted ios-ui on
`e64b33a` failed Select and sensitive-type when those controls sat in a
three-button HStack and Select itself used a plain wrapping label that
did not take the tap.
