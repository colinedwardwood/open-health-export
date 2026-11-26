The overdue alarm now also covers a destination that has never succeeded (it counts from
the later of enabling and the last success), is no longer pushed back by an empty read
that never ran, and is re-armed at launch and foreground. Queue expiry runs on every
background wake and names the destinations it cleared. Status explains when Background
App Refresh is off or restricted, or Low Power Mode is on (#63).
