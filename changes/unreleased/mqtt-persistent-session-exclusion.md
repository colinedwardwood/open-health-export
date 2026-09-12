QA-11 / ADR-0003: refuse MQTT CleanSession=0 at destination construction and
on `.tributary` import instead of silently connecting with a clean session.
CONNECT still always carries CleanSession=1.
