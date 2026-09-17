Destinations now persist an AR-15 exporter role for this installation.
Designated installations may run automatic observer, foreground catch-up, and
background exports. A destination set to Manual only rejects every automatic
trigger while retaining explicit app, Shortcut, and widget-control exports.

The role is two wrapping buttons on the destination status card, survives later export
outcomes in `status.json`, and tells the user to keep exactly one installation
automatic for a shared destination. Observer registration and background-task
handling both enforce the same policy; the export entry point also fails closed
if either boundary is bypassed.
