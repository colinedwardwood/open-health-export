Status “Where your data goes” and Settings use the wrapping control style,
and destination export-role choices are Text labels rather than UIKit button
titles, so the destination-status accessibility audit can scale them.
Contrast classification uses frame-versus-window instead of isHittable so
empty-browser audits spend less time in XCTest round-trips.
