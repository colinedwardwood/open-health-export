Sharing a diagnostic bundle no longer depends on a confirmation button. The share
affordance now exists only below the bundle's last line, so it cannot be reached without
traversing the content by scroll, VoiceOver or Full Keyboard Access — the S9 design for
R-26, where the guarantee is a fact about the view hierarchy rather than a state machine.
Reaching the end is evidenced by scroll visibility, not `onAppear`, because a scroll view
builds every child whether or not it is on screen.
