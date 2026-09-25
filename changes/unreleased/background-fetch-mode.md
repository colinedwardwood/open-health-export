Background app refresh can now be scheduled: the app declares the `fetch`
background mode its refresh task needs, submits both background tasks on every
launch and foreground, and names any request iOS refuses on Status (#29).
