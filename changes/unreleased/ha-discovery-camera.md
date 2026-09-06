### HA MQTT discovery and camera scan path

Catalogue rows now carry Home Assistant unit / device class / state class. Discovery JSON is
device-based, retained only for `homeassistant/device/<id>/config` and the `online` status byte
string, and is rejected if it contains sample keys. The iOS harness asks for camera access before
VisionKit, surfaces why scan is unavailable, and still accepts paste.
