# Motion: the "same box" transition

**Opt-in.** This is a technique to use when it's asked for ("make it the same box", "like Week to Day"). It is not the default for every animation; ordinary transitions keep the normal motion rules (200–250 ms, `easeOutCubic`, no bounce).

When it's asked for, the thing you tapped **becomes** the next view. Its edges grow out to the next view's edges, and what's inside it turns into the next view's contents, at their exact places. Nothing swaps at the end. Going back is the same motion in reverse.

The reference is **Schedule, Week ⇄ Day** (24 Oct 2026). Tap a date in Week: that column's box grows on all four sides into Day's card. Its chips grow into Day's blocks, its hours stretch to Day's, and the last frame *is* Day.

---

## Rules

1. **One box.** The tapped element is the box. It grows from its own rectangle to the destination's card (left, right, top and bottom all move). The rest of the old view fades or is squeezed away around it.
2. **Contents transform; they don't swap.** Inside the box, every measurement moves from the source's value to the destination's: positions, sizes, insets, gaps, scale (for example minutes → pixels), text styles (`TextStyle.lerp`). Where the two looks differ (Week chip → Day block), draw both **in the same moving rectangle** and cross-fade them while the rectangle itself moves.
3. **The last frame is the destination.** At t = 1 the source draws exactly what the destination draws: the same card edge, padding and height, insets, styles, selection ring and scroll position. The hand-over is then invisible. Only parts the source can't have (a side panel, a legend) fade in.
4. **Hand state over, both ways.** Scroll offset, selection and range carry across. The destination opens where the source was and never re-scrolls or re-selects itself afterwards (no "jump to now" after a transition). Going back starts from the destination's exact frame.
5. **Reverse = the same motion backwards.**
6. **Timing.** 250 ms per leg (`CruMotion.standard`), `easeOutCubic` out and its flip on the way back, no bounce, no overshoot. Look changes (chip → block) run over the middle of the motion (about t 0.15 → 0.85). Always go through `CruMotion.of(context)` so reduced-motion turns it off.
7. **At rest, nothing changes.** The resting view must look exactly as before (the goldens must not move). Keep the widget tree the same shape at rest and while animating: wrap in `Opacity`/`ClipRect`/`OverflowBox` that are no-ops at t = 0, rather than swapping widgets when the animation starts or ends (that loses scroll and hover state).

### Opening from a button

If it's asked for where there's no matching content to transform (a button opens a panel), use the same box idea: the button's own box grows into the panel's card while the button's icon fades out. The panel's content is scaled with the box (never cut off by it) and fades in once the box is mostly open. Closing shrinks it back into the button.

### Don't (when building one of these)

- Cross-fade two different layouts once the motion has settled.
- Reveal a still page through a growing clip window.
- Let the destination re-scroll, re-select or re-layout after the hand-over.
- Run longer than 250 ms per leg, or use bounce or overshoot.

---

## How Week ⇄ Day is built

| Piece | Where | What it does |
|---|---|---|
| The in-between values | `lib/features/appointments/presentation/widgets/week/week_focus.dart` | `WeekFocus(index, t)` holds every value that moves: px per minute, gutter width, label inset and lift, block inset, `dayLook` (the chip → block fade). `WeekColumnsRow` widens the opening column to the full grid; the other columns keep their layout and are squeezed, clipped and faded. |
| The growing box | `week/appointments_week_view.dart` | An `AnimationController` drives t. `_OpeningCardPainter` paints the week's card fading out and the box growing from the column (`_openingColumn`, so it hugs the column) to Day's card. The card padding, height and scroll padding lerp to Day's. When it finishes it calls `openDay` and leaves `handoffScroll`; coming back from Day it starts at t = 1 and folds. |
| Contents morphing | `week/week_grid.dart` | In the opening column, a `WeekBlock` and Day's own `DayBlock` sit in the same `Positioned`, whose rectangle lerps from chip to Day block; they cross-fade by `dayLook`. Hour labels lerp to Day's style and position. The column line, today's tint and (for another day) the time pill fade away. |
| Hand-over | `data/providers/appointments_providers.dart`, `day/day_grid.dart`, `day/appointments_day_view.dart` | `handoffScroll` / `dayScroll` / `takeWeekFromDay` carry scroll and direction across. Day draws its week's hours (`hoursFrom`) and starts at the handed-over scroll. |

---

## Recipe for a new transition

1. **List what differs.** Source rectangle and destination card rectangle, then every measurement that differs: padding, insets, gaps, scale, text styles, scroll origin, selection.
2. **Put the in-between values in one object** (like `WeekFocus`) with getters lerped by t, so the layout code just reads them.
3. **Build the morph inside the source view**, using the destination's own widgets for the end look.
4. **Hand state over** through the controller; the destination reads it once in `initState`.
5. **Check it with frames, not by eye.** Render frames in a throwaway widget test (the `test/appointments` harness, `RenderRepaintBoundary.toImage`), then diff the last source frame against the destination over the card. The difference should be antialiasing only. Do the same for the first frame back. Delete the test afterwards.
6. **Check the resting goldens didn't move.**

## Checklist before calling it done

- [ ] Box grows on all four sides from the tapped element to the destination card.
- [ ] Contents move and restyle in place; any look change cross-fades within the same moving rectangle.
- [ ] Last frame ≈ destination (pixel diff), first frame back = destination.
- [ ] Scroll and selection carried both ways; no jump after the hand-over.
- [ ] 250 ms, `easeOutCubic`, no bounce; `CruMotion.of(context)` used.
- [ ] Resting goldens unchanged; Day and Evening both checked.
