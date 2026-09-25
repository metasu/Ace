---
name: static-html-browser-games
description: >-
  Build or refactor pure static HTML/CSS/JS browser games (no build step):
  multi-file structure, GSAP UI choreography, canvas rAF loops, tablet/touch
  dual-player anti-mis-tap, offline-safe CDN fallbacks, dual-player letter-spell
  modes. Use when the user has a single-file HTML game, wants GSAP polish,
  tablet/pad multi-touch two-player same-device play, spell-by-letter word games,
  or asks whether design-md / gsap-skills apply to static games.
---

# Static HTML Browser Games

## When to use

- User path or artifact is a **static** `index.html` / single-file game (no React/Vite required)
- Goals include: **split monofile**, **GSAP motion**, **tablet / 平板**, **双人同屏**, **防误触**, **字母拼写**
- Evaluating agent repos like `awesome-design` (DESIGN.md skins) or `gsap-skills` for a game

## Role of external skill packs

| Pack | Role in a static game | Not |
|------|------------------------|-----|
| `gsap-skills` / GSAP | UI timing, entrances, feedback, result screens | Full game loop / physics engine |
| `awesome-design` / DESIGN.md | Menu/HUD skin tokens (colors, type, radius) | Sprites, levels, collision |

Prefer **GSAP for discrete UI**; keep **continuous track/progress on canvas + `requestAnimationFrame`**.

## Default multi-file layout

```text
game/
├── index.html
├── css/styles.css
├── js/
│   ├── data.js           # content (word banks, levels) → window.*
│   ├── audio.js          # Web Audio module
│   ├── canvas-*.js       # draw loop
│   ├── animations.js     # GSAP wrapper + reduced-motion / no-gsap fallback
│   ├── touch.js          # pointer confirm-tap + global guards
│   └── game.js           # state machine / rules
└── README.md             # how to serve on LAN for tablets
```

Keep a monofile backup only if the user already had one; **new entrypoint is `index.html`**.

**User preference (this workspace):** often wants a **final all-in-one HTML** that can be double-clicked (inline CSS/JS; optional CDN with offline fallback). Multi-file is fine while developing; deliver monofile when asked.

## GSAP patterns (vanilla)

1. Load CDN once; wrap all motion in `canAnimate() = gsap && !prefers-reduced-motion`.
2. Use **timeline + stagger** for select/result screens; **single tweens** for score pop / wrong shake.
3. Prefer transform aliases: `x`, `y`, `scale`, `autoAlpha` — not `left`/`top`/`width`.
4. Feedback overlays: `pointer-events: none` so animations never steal the next tap.
5. After GSAP runs on a centered toast, **clearProps / reset inline styles** so CSS `translate(-50%,-50%)` still works offline.

```html
<script src="https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/gsap.min.js"></script>
```

If CDN fails, game logic must still run (animations.js no-ops).

## Tablet + dual-player anti-mis-tap (required for 平板双人)

Implement a small `TouchTap` helper; do **not** rely on bare `click` alone.

### Confirm tap

1. `pointerdown` → record `pointerId`, start x/y/time, add `is-pressing`
2. `pointermove` → if distance > ~18px, **cancel** (scroll/drag, not tap)
3. `pointerup` → fire handler only if not cancelled, duration < ~700ms
4. **Debounce same element** ~250–300ms
5. Swallow follow-up `click` to avoid double fire
6. Support keyboard Enter/Space on `[data-tap]` for desktop

### Dual-player same device

- Left/right panes: **separate event roots** + `bindTapDelegate` so two fingers can press different buttons
- Track state **per `pointerId`**, never a single global “finger”
- On correct finish: set a short **question lock** so the other side’s delayed `pointerup` cannot score the same round
- Hit targets ≥ ~48px (options often 58–72px in landscape)

### Global guards

- `viewport`: `maximum-scale=1`, `user-scalable=no`, `viewport-fit=cover`
- Safe areas: `env(safe-area-inset-*)`
- `touch-action: manipulation` on body/buttons; `touch-action: none` on non-interactive canvas track
- Suppress double-tap zoom on interactive targets; block `gesturestart` zoom where needed
- `user-select: none`, no callout; feedback layer never captures pointers

## Dual-player letter-spell mode (harder than multi-choice)

When multi-choice feels too easy, switch to **order-correct letter spelling**:

1. Center shows **Chinese meaning only** (+ letter count tip). Do not show the English word.
2. Each player has: spell slots + letter bank + backspace/clear.
3. Letter bank = all letters of the target (with multiplicity) + 3–6 distractors; shuffle; min ~10 keys.
4. Accept letters **only in correct order**. Wrong letter → that player out for the round. Full match → score + lock opponent.
5. Backspace/clear restore used letter buttons for that player until they are out or the round ends.
6. Target score / timer: slightly more generous than 4-option mode (e.g. 8 pts / 120s vs 10 / 90).

### Letter grid layout

- Use fixed columns: `.pane-options { grid-template-columns: repeat(3, 1fr); }` — **3 letters per row**.
- Do **not** leave 2-column grids from old multi-choice options.
- Put letter/spell CSS in **global** stylesheet, not only inside landscape `@media` (otherwise narrow/portrait looks broken).

## Canvas track / continuous motion

- DPR: set `canvas.width/height` from CSS size × `min(devicePixelRatio, 2)`, `setTransform(dpr,…)`
- Resize on `resize` / `orientationchange` (debounce ~200ms after rotate)
- Interpolate progress each frame (`x += (target - x) * 0.12`) rather than GSAP-tweening every score tick for the whole loop
- Dashed center line: choose `lineDashOffset` direction so cars feel forward (not reverse); speed is independent of car x

## Large monofile edits

- Prefer a **temp Python script file** over giant `python - <<'PY'` heredocs on Windows/bash (quote/EOF breakage).
- After rewrite: assert key symbols present; `node --check` extracted JS; brace/paren balance.
- When consolidating multi-file → monofile, delete split sources only after the single file is verified.

## Serve for real tablets

Prefer LAN static server over `file://` when multiple scripts + CDN:

```bash
cd game && python -m http.server 8080
# tablet → http://<host-ip>:8080/
```

Monofile with one CDN script can open via `file://` if offline fallback is solid.

## Pitfalls

- **CSS hover on touch**: avoid hover-only affordances; use press classes from pointer handlers
- **GSAP + CSS transform fight** on centered modals: set GSAP `xPercent/yPercent` carefully or clear props after hide
- **DESIGN.md SaaS skins** on kids’ games: borrow tokens, don’t force marketing-site layout
- **Monofile extract**: parse `UNITS` / large JSON with a one-shot Python extract before rewriting modules
- **Audio unlock**: resume `AudioContext` on first `pointerdown`
- **Spell CSS trapped in media query**: letter/spell styles must be global
- **2-col leftover from multi-choice**: force `repeat(3, 1fr)` for letter banks
- **Heredoc patch scripts on Windows git-bash**: write `.py` to disk then run

## Verification checklist

- [ ] Two fingers can tap P1 and P2 options in the same second
- [ ] Sliding finger across a button does not count as answer
- [ ] Double-tap does not zoom or fire twice
- [ ] Feedback toast does not block the next option
- [ ] GSAP blocked / offline → still playable
- [ ] Rotate tablet → track resizes without broken DPR
- [ ] Letter-spell: 3 letters per row; wrong letter outs player; first full word scores
- [ ] Backspace restores used letters before round end

## References

- `references/letter-spell-dual-player.md` — dual-player spell-by-letter rules, letter bank, 3-col grid
