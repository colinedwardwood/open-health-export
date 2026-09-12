# Simulator demo quickstart

This path uses synthetic values only. It does not request Health access and should take less than ten minutes after the project has built.

1. Run `scripts/generate-project.sh`.
2. Open `OpenHealthExporter.xcodeproj`, select the `ExporteriOS` scheme and any iOS 18-or-later simulator, then run.
3. Read the first-run disclosure and choose **Continue**.
4. In **Data browser**, turn on **Use demo values**.
5. Scroll to **DEMO MODE — synthetic data**.
6. Type `local-file` exactly in the confirmation field.
7. Choose **Export demo dataset (every catalogue metric)**.
8. Wait for **Demo export finished. Files are DEMO- prefixed.**
9. Confirm that the Measurements section reports successful demo runs. Every emitted record is synthetic and carries `demo: true`; the demo archive is separate from a real destination.

For an automated check of the same safety boundary, run:

```sh
xcodebuild \
  -project OpenHealthExporter.xcodeproj \
  -scheme ExporteriOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ExporteriOSUITests/ExporterUITests/testDemoExportStaysDisabledUntilTypedConfirmation \
  test
```
