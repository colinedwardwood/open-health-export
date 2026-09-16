---
category: fixed
---

The UI suite can now find a control that sits above where the last one left the
page. It only ever scrolled one way and refused to consider anything already
scrolled past, so a test that filled a form in reading order rather than layout
order found the next field only when it happened to still be on screen. The
diagnostic preview is also rendered one line per view, like the summary lines
beside it, rather than as one view holding the whole bundle.
