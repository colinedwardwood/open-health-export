# Sharing a crash log

The app sends no crash reports. If it crashed and you want to help, you can share a log by hand.

## What a crash log contains

An `.ips` file records the app version, iOS version, device model, and the code location of the
crash. It can also contain file paths and names of things like destination hostnames if they
appear in an error message. It should not contain Health values, but check before you send.

## Find it on your iPhone

1. Open Settings, then Privacy and Security, then Analytics and Improvements, then Analytics Data.
   (Menu names vary a little between iOS versions.)
2. Look for entries that start with the app's name and end in a date. If the list is empty,
   iOS analytics sharing may be off; crash logs are only kept there when it is on.
3. Tap the newest matching entry. Use the share button to send it to yourself.

## Check it, then send

1. Open it as text. Search it for your server names, usernames and any numbers that look like
   Health readings. Delete those lines if you find any, or tell us instead of sending.
2. Attach it to a GitHub issue (see `SUPPORT.md`), or send it to support by email.
3. Say what you were doing, the app version (Settings, About) and your iOS version.

## What we do with it

Use it to find the crash and delete it afterwards. Counts only (not the file) go into the
monthly support log.
