# 18 - Accessibility Checklist (Tier B hardening)

Manual checks to run before each release. Automate where possible later.

- [ ] All interactive elements reachable by keyboard (Tab/Enter/Space).
- [ ] Focus order follows visual order; no focus traps except dialogs.
- [ ] Every IconButton has a tooltip; every image has semanticLabel.
- [ ] Color contrast >= 4.5:1 for text, 3:1 for large text (WCAG AA).
- [ ] Status not conveyed by color alone (icons/text added).
- [ ] Form fields have labels and error text announced.
- [ ] Screen reader (NVDA/VoiceOver) smoke test on Dashboard, Ledger, Payments.
- [ ] No horizontal scroll on mobile (320px width).
- [ ] Touch targets >= 44x44 dp.
- [ ] Reduced motion respected (no auto-animating charts on scroll).