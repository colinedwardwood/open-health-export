Prove the widget URL opens destination status in the host app.

SpringBoard widget placement is not a CI-stable gate. The widget's
`openhealthexporter://status` route is: a debug launch seed drives the same
`onOpenURL` path the widget uses, and the empty widget view now has a
`widget-empty` identifier.
