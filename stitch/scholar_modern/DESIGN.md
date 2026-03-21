# Design System Specification: The Academic Atelier

This design system is a premium framework for modern educational interfaces, moving beyond the "classroom" aesthetic into a high-end "editorial" experience. It treats information as a curated exhibition, using sophisticated depth, intentional white space, and a refined tonal palette to foster focus and authority.

---

## 1. Overview & Creative North Star: "The Digital Curator"
The Creative North Star for this system is **The Digital Curator**. Unlike standard educational platforms that feel cluttered or overly "gamified," this system treats learning material with the reverence of a high-end journal. 

We break the "template" look through:
*   **Intentional Asymmetry:** Using the Spacing Scale to create unbalanced but harmonious layouts that guide the eye.
*   **Editorial Scale:** Drastic contrast between `display-lg` headlines and `body-md` content to establish a clear narrative hierarchy.
*   **Breathing Room:** Utilizing the `20` (7rem) and `24` (8.5rem) spacing tokens to isolate key concepts, ensuring the UI never feels "crowded."

---

## 2. Colors & Surface Philosophy

The palette transitions from the deep, scholarly authority of Navy (`primary`) to the modern, energetic pulse of Teal (`secondary`).

### The "No-Line" Rule
**Explicit Instruction:** Designers are prohibited from using 1px solid borders for sectioning content. Boundaries must be defined solely through background color shifts. 
*   *Example:* A lesson module should use `surface_container_low` sitting on a `surface` background. The change in tone is the border.

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers, like stacked sheets of fine vellum.
*   **Base Layer:** `surface` (#f8f9fa)
*   **Sectioning Layer:** `surface_container_low` (#f3f4f5) for broad content areas.
*   **Interactive Layer:** `surface_container_lowest` (#ffffff) for primary cards and input fields to make them "pop" against the background.

### The "Glass & Gradient" Rule
To avoid a flat, "out-of-the-box" feel, use **Glassmorphism** for floating navigation or overlays:
*   **Token:** `surface` at 70% opacity with a `24px` backdrop-blur.
*   **Signature Textures:** Apply a linear gradient from `primary` (#00162a) to `primary_container` (#0d2b45) on hero sections or primary CTAs to add a sense of "visual soul."

---

## 3. Typography: Precision & Narrative

The system uses two distinct typefaces to balance personality with utility.
*   **Headlines (Manrope):** A geometric sans-serif that feels precise and architectural. Use `display-lg` (3.5rem) for chapter starts to create a "title page" feel.
*   **Body (Inter):** A highly legible workhorse. Use `body-lg` (1rem) for core educational content to ensure high reading stamina.

**Hierarchy Note:** Always lead with `headline-lg` in `primary` color for module titles, followed by `body-md` in `on_surface_variant` (#43474d) for descriptions. This tonal shift creates an effortless secondary hierarchy.

---

## 4. Elevation & Depth: Tonal Layering

Traditional shadows are replaced by **Tonal Layering**. We achieve depth through the "stacking" of surface tokens.

*   **The Layering Principle:** Place a `surface_container_highest` (#e1e3e4) element inside a `surface_container` (#edeeef) parent to create a recessed, "inset" feel for code blocks or quotes.
*   **Ambient Shadows:** When an element must float (e.g., a "Start Quiz" FAB), use a large blur (32px) at 6% opacity. Use the `on_surface` color as the shadow base—never pure black—to maintain a natural, ambient light feel.
*   **The "Ghost Border" Fallback:** If a border is required for accessibility, use the `outline_variant` token at **20% opacity**. 100% opaque borders are strictly forbidden as they break the editorial flow.

---

## 5. Components

### Buttons & CTAs
*   **Primary:** Gradient of `primary` to `primary_container` with `on_primary` text. Use `lg` (1rem) roundedness.
*   **Secondary:** `secondary_container` background with `on_secondary_container` text. This is your "Action" teal.
*   **Tertiary:** No background. Use `primary` text with a subtle `surface_variant` hover state.

### Input Fields & Cards
*   **Cards:** Use `surface_container_lowest` with `xl` (1.5rem) roundedness. No borders. Use the spacing token `6` (2rem) for internal padding.
*   **Inputs:** Use `surface_container_high` with `md` (0.75rem) roundedness. On focus, transition the background to `surface_container_lowest` and add a "Ghost Border."

### Lists & Progress
*   **Forbid Dividers:** Do not use lines to separate list items. Use the spacing scale `3` (1rem) to create clear vertical "gutters" of white space between items.
*   **Progress Indicators:** Use the `secondary` (Teal) color against a `surface_variant` track for a vibrant, high-contrast indicator of completion.

### Bespoke Educational Components
*   **Focus Block:** A high-contrast container using `tertiary_container` with `on_tertiary_container` text for "Key Takeaways" or "Formulas." 
*   **Curated Deck:** A horizontal-scrolling card group where cards use `surface_container_low` and `xl` roundedness, creating a "bento-box" style layout.

---

## 6. Do’s and Don’ts

### Do:
*   **Do** use asymmetrical margins (e.g., more padding on the left than the right in headers) to create an editorial, "magazine" feel.
*   **Do** use `secondary_fixed` for success states or high-priority badges.
*   **Do** rely on typography weight (SemiBold vs Regular) rather than color alone to show importance.

### Don’t:
*   **Don’t** use pure black (#000000) for text. Always use `on_surface` (#191c1d).
*   **Don’t** use `sm` roundedness for large containers; it feels too "technical." Use `xl` or `lg` to keep the app "friendly but precise."
*   **Don’t** use "Drop Shadows" to define cards. Use the Surface Hierarchy (background shifts) first. Shadows are a last resort for floating UI only.