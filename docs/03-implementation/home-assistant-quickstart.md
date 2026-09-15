# Home Assistant webhook quickstart

This destination sends the complete native NDJSON feed to a Home Assistant
automation webhook. Home Assistant does not import or backdate historical sensor
states from the feed by itself. The automation decides what to do with each POST.

## Prepare Home Assistant

1. In Home Assistant, create an automation with a **Webhook** trigger.
2. Give the webhook a new, unguessable ID. Keep the default POST method enabled.
3. Add a harmless first action that makes receipt visible, such as creating a
   persistent notification. Do not put the webhook ID in an issue or screenshot.
4. Save the automation and note:
   - the Home Assistant base URL, such as `https://homeassistant.example.net`;
   - the webhook ID. The app stores this separately as a credential.

For a plain-HTTP Home Assistant on a trusted local network, the app requires the
explicit **Allow plain HTTP to Home Assistant (unsafe)** opt-in. HTTPS is the
default.

## Configure the app

1. Complete the app's first-run disclosure and Health read selection.
2. On **Data**, choose **Home Assistant** as the export destination and select
   at least one type plus a start date.
3. On **Destinations**, enter the base URL and webhook ID.
4. Choose whether metered networks are allowed.
5. Select **Test Home Assistant webhook**. Review the resolved host, transport,
   and canary preview, then confirm the destination. No Health values move during
   this test.
6. Select **Export one page (Home Assistant webhook)**.

## Verify both ends

1. In Home Assistant, open the automation trace and confirm that one webhook
   invocation completed.
2. In the app's **History**, confirm that the run names the Home Assistant
   destination and records its counts and outcome.
3. Return to **Status** and confirm that Home Assistant has a destination row.

If another iPhone or iPad uses the same webhook, leave exactly one device set to
**Automatic and manual**. Set every other device to **Manual only** on its
destination status card; aggregate bucket keys intentionally converge across
devices.

This procedure still requires end-to-end verification by a non-maintainer on a
clean Home Assistant installation before release. Repository automation verifies
the webhook contract against the oldest and current supported Home Assistant
versions; it does not substitute for that external quickstart pass.
