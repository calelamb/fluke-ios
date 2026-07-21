# Full-launch accessibility manual audit

Run this checklist on a physical iPhone before App Store submission. Record the device, iOS build,
tester, date, and a pass/fail note for every row; simulator automation is supporting evidence only.

- Traverse Sightings, Whales, Identify, Learn, and You with VoiceOver. Verify logical order,
  descriptive labels and hints, distinct status/action elements, and no unlabeled actionable control.
- Open Add Sighting. Deny camera permission, confirm selection-only PhotosPicker remains usable, force
  each validation error, and verify VoiceOver focus moves to the first invalid field. Submit online and
  offline and verify success/queued announcements. Confirm the escape gesture respects the dirty guard.
- Open Movement from a whale and a sighting. Verify the close control and escape gesture, season
  controls, map summary, focused sighting, playback, date scrubber, and sparse Submit action.
- Open Atlas and traverse Timeline, Range, Trace, and Predict. Verify each visual has one concise text
  summary, decorative coastline/paths/cells are skipped, controls expose selected state, and escape
  closes the cover.
- Repeat the full traversal at Accessibility XXXL in portrait. Verify required copy has no truncation,
  controls remain at least 44 by 44 points, and horizontal controls become vertical layouts or menus.
- Repeat with Increase Contrast and Differentiate Without Color. Verify state never depends on color.
- Repeat with Reduce Transparency. Verify control shelves remain opaque and legible.
- Repeat with Reduce Motion. Verify tracks appear without animation, playback is disabled with an
  explanation, and no information is communicated only through motion.
- Confirm Identify in the shipping disabled state does not request camera or photo permission.
- Confirm the coordinate picker never requests device location and camera denial has actionable copy.
