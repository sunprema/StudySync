---
name: frontend
description: "Use this skill working with frontend when developing HTML on live views."
---

## Additional References

- [UI_philisophy] (references/Refactoring_UI.pdf)

## IMPORTANT RULES

- Phoenix live view uses Daisy UI. You should use DaisyUI components where available.
- use Tailwind CSS class names liberally. You dont have to force yourself with DaisyUI components if it doesnt fit your need.
- create Phoenix components in /lib/genie_web/components/core_components.ex for creating reusable components.
- Ask Questions if requirements are not clear.
- Use LiveSvelte if the components requires client state and better user interactions.
- WE are using Svelte 5. Make sure you adhere to Svelte 5 syntax.
- Use Svelte MCP server if you have any questions on using Svelte 5

## CSS / Styling

- This project uses DaisyUI + Tailwind. Before introducing custom class names, check that they don't collide with DaisyUI component classes (e.g., `hero`, `steps`, `card`).
- When integrating standalone HTML/landing pages, use a dedicated layout to avoid Tailwind Preflight squeezing content width.

## Refactoring UI — philosophy

- Start with a single feature, not the app shell. Don't design the nav until you have something to put in it.
- Defer detail. Sketch in grayscale; introduce color only after spacing/contrast/size carry the hierarchy.
- Don't design too much up front — build the simple version, iterate on the real thing.
- Pick a personality early (typography, color, border-radius, language) and constrain your choices into systems.

# Hierarchy is Everything

- Visual hierarchy is what makes a UI feel "designed." Not all elements are equal — make the important things obvious by de-emphasizing the rest.
- Don't lean only on font size. Use weight + color too. 2–3 colors, 2 weights (400/500 + 600/700) is plenty.
- Grey text on white = reduced contrast. On colored backgrounds, hand-pick a desaturated tint of the background hue instead.
- Labels are a last resort — context/format usually tells you it's a price or email. When you do need a label, treat it as the supporting element, not the data.
- Separate visual hierarchy from document hierarchy: an <h1> doesn't have to be huge.
- Balance weight & contrast: heavy icons → soften the color; thin borders → thicken to compensate for soft color.
- Action hierarchy beats semantics: every page has one primary, a few secondary, and tertiary actions — style them accordingly. Destructive ≠ red-and-bold.

# Layout & Spacing

- Start with too much white space and remove. Don't add it as an afterthought.
- Build a non-linear spacing/sizing scale (no two values <25% apart). Base it on 16px.
- Don't fill the whole screen. Use a max-width on components — shrink only when needed.
- Grids are overrated. Sidebars want fixed width; main content flexes.
- Relative sizing doesn't scale across screen sizes. Headlines and body shrink at different rates.
- Avoid ambiguous spacing: more space around a group than within it.

# Designing Text

- Hand-craft a type scale (~6–8 sizes). Avoid em units for sizing — use px/rem.
- Pick fonts with 5+ weights; popular fonts are popular for a reason.
- Line length 45–75 characters; line-height inversely proportional to font size and proportional to line length.
- Align mixed font sizes by their baseline, not center.
- Not every link needs a color — a font weight bump or hover-only underline is often enough.
- Left-align long-form text; right-align numbers; only justify with hyphenation.
- Tighten letter-spacing for big headlines; loosen it for ALL CAPS.

# Working with Color

- Use HSL, not hex. You need way more colors than five — typically 8–10 shades each of: greys, primary, accents (success/warn/danger).
- Define shades up front (100→900). Don't lighten/darken on the fly.

# Starting from Scratch

- Start with a single feature, not the app shell. Don't design the nav until you have something to put in it.
- Defer detail. Sketch in grayscale; introduce color only after spacing/contrast/size carry the hierarchy.
- Don't design too much up front — build the simple version, iterate on the real thing.
- Pick a personality early (typography, color, border-radius, language) and constrain your choices into systems.

# Hierarchy is Everything

- Visual hierarchy is what makes a UI feel "designed." Not all elements are equal — make the important things obvious by de-emphasizing the rest.
- Don't lean only on font size. Use weight + color too. 2–3 colors, 2 weights (400/500 + 600/700) is plenty.
- Grey text on white = reduced contrast. On colored backgrounds, hand-pick a desaturated tint of the background hue instead.
- Labels are a last resort — context/format usually tells you it's a price or email. When you do need a label, treat it as the supporting element, not the data.
- Separate visual hierarchy from document hierarchy: an <h1> doesn't have to be huge.
- Balance weight & contrast: heavy icons → soften the color; thin borders → thicken to compensate for soft color.
- Action hierarchy beats semantics: every page has one primary, a few secondary, and tertiary actions — style them accordingly. Destructive ≠ red-and-bold.

# Layout & Spacing

- Start with too much white space and remove. Don't add it as an afterthought.
- Build a non-linear spacing/sizing scale (no two values <25% apart). Base it on 16px.
- Don't fill the whole screen. Use a max-width on components — shrink only when needed.
- Grids are overrated. Sidebars want fixed width; main content flexes.
- Relative sizing doesn't scale across screen sizes. Headlines and body shrink at different rates.
- Avoid ambiguous spacing: more space around a group than within it.

# Designing Text

- Hand-craft a type scale (~6–8 sizes). Avoid em units for sizing — use px/rem.
- Pick fonts with 5+ weights; popular fonts are popular for a reason.
- Line length 45–75 characters; line-height inversely proportional to font size and proportional to line length.
- Align mixed font sizes by their baseline, not center.
- Not every link needs a color — a font weight bump or hover-only underline is often enough.
- Left-align long-form text; right-align numbers; only justify with hyphenation.
- Tighten letter-spacing for big headlines; loosen it for ALL CAPS.

# Working with Color

- Use HSL, not hex. You need way more colors than five — typically 8–10 shades each of: greys, primary, accents (success/warn/danger).
- Define shades up front (100→900). Don't lighten/darken on the fly.
- As lightness moves away from 50%, bump saturation to keep colors from looking washed out. Or rotate hue toward a brighter neighbor (yellow/cyan/magenta) to brighten without washing.
- Greys can (and usually should) be slightly saturated — warm or cool — for personality.
- For accessibility on colored backgrounds, flip the contrast (dark text on tinted background) instead of darkening the background to fit white text.
- Never rely on color alone — pair with icons, weight, or contrast.

# Creating Depth

- Light comes from above. Top edge lighter, bottom edge darker for raised; opposite for inset.
- Shadows = elevation. Tighter/smaller for slight lift (buttons), larger/softer for modals. Define a 5-level shadow scale.
- Two-shadow technique: a soft larger shadow (direct light) + a tight darker shadow (ambient). The tight one fades as elevation increases.
- Even flat designs convey depth — via background color (lighter = closer) and overlapping elements across section boundaries.

# Working with Images

- Use real, high-quality photos from day one. No placeholders.
- Text on images needs consistent contrast: overlay, lower image contrast, colorize, or text-shadow as a soft glow.
- Everything has an intended size. Don't scale 16px icons up to 64px (use a container instead). Don't shrink full screenshots — crop or simplify.
- For user-uploaded images: fix the container shape via background-size: cover; use an inner shadow (not a border) to prevent background bleed.

# Finishing Touches

- Supercharge defaults: replace bullets with icons, restyle checkboxes, custom underlines on links.
- Accent borders (top of card, left of alert) cheaply add polish.
- Decorate backgrounds: tinted panels, subtle gradients (hues <30° apart), repeating patterns, geometric shapes. Always low-contrast.
- Empty states are a first impression — design them deliberately, hide noise (filters, tabs), put a CTA front-and-center.
- Use fewer borders. Replace with shadows, two background colors, or just more spacing.
- Think outside the box: dropdowns can have columns + icons, tables can merge columns, radio buttons can be cards.

# Leveling Up

- Look for decisions you wouldn't have made.
- Rebuild interfaces you admire from scratch — without peeking at devtools.

How this maps to StudySync Direction 01 (Margin Notes):

- The palette already follows the book's "lots of shades, warm-saturated greys" rule — --paper/--paper-2 are warm-saturated, not true grey, and terracotta is the lone accent.
- The serif/mono/UI split + tabular numerals matches the "type scale + personality" chapter.
- Margin column over a tinted --paper-2 surface is the "two background colors instead of borders" trick.
- Footnote markers as small terracotta superscripts is "emphasize-by-de-emphasizing" applied to inline anchors.
- The "no drop shadows on flat surfaces" rule in CLAUDE.md aligns with the book's "even flat designs can have depth" — depth via color + overlap, not shadow.
