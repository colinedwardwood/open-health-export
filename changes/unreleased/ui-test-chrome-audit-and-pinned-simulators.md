Measure the navigation and tab bars when deciding which accessibility contrast
findings are SDK-owned, instead of assuming a fixed top cutoff. The floating tab
bar fades the band of content above it, so correctly coloured text near either bar
was reported as an app defect on some screen sizes and not others.

Pin the XCUITest simulator models in scripts/ui-test-simulator.sh. macos-build
took whichever device the runner listed first, so an accessibility audit could
pass or fail on the same commit depending on the runner image.
