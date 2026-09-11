Close three security disclosure gaps that had no automated gate.

SEC-27: notification bodies are enumerated over every notice kind and asserted
to carry no health value, no type name and no destination address. The renderer
now replaces an address-shaped destination with a generic term, so a caller that
hands it a hostname cannot put one on the Lock Screen.

SEC-64: the device-only keychain is disclosed above every credential field, and
a UI test asserts the disclosure really does precede the field.

SEC-45: sharing a diagnostic bundle shows a one-time warning that the copy
leaves this app's protection, and the share control only appears once that is
acknowledged. R-26 still decides where it sits — below the bundle's last line.
