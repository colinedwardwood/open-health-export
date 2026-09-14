Imported-draft setup buttons use destination-kind identifiers. UI tests
search Destinations without cycling other tabs, skip panes that do not
contain the control, and name the navigation-bar scroll-edge fade the
same way as the tab-bar fade. Hunting a missing control by scrolling is
limited to a named tab so other panes are not swiped forty times.
DEBUG companion seeds clear a leftover pairing slot so import is not
refused as an occupied destination. Companion pairing sits next to
configuration import so the Mac name and pairing controls are reachable.
The pairing confirmation control is asserted by its VoiceOver label.

