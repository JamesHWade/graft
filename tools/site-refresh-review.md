# Site refresh review

Baseline built from merged Graft 2de56e6. Reviewed homepage, quickstart,
ecosystem guide and tool reference in the in-app browser.

- At 320px, the floated 139px logo squeezed the homepage hero to a narrow
  column, splitting almost every heading word. Clear the hero and reduce the
  small-screen logo; retain the existing frog artwork.
- At desktop size, the long hero heading pushed both actions below the first
  screen. Shorten the outcome statement and reduce its type and padding.
- The homepage duplicated most of the quickstart, including manually maintained
  results. Move the tutorial to its existing URL and expose task-based routes.
- “Safe to put in front of a model” and broad trust claims exceeded validation
  and receipt guarantees. Explain acceptance, exact reuse and verification limits.
- The Learn menu mixed authoring, retrieval, hosting and representation design.
  Give integrations a separate menu and preserve existing article URLs.

## Validation

Reviewed the homepage, getting-started guide, ecosystem guide and
`graft_tools()` reference at 320, 768 and 1280 pixels in light and dark modes.
Screenshots were inspected in the task conversation. All four pages stayed
within the viewport at every size; long headings wrapped without splitting
words. The 72px mobile logo no longer squeezes the hero. Code blocks and the
wide integration table scroll within their own bounds.

The native mobile menu and theme switch work. Keyboard search for “reuse” finds
the exact-basis guide; Arrow Down changes selection and Enter opens the selected
published URL. Tab navigation shows a 3px focus outline with a 3px offset.
Text, links and buttons remain legible in both themes. The decorative logo has
empty alt text beside the package heading. The existing reduced-motion rule
removes transitions and hover transforms; no new animation was introduced.

Search also exposed `CONTEXT.md` as an unintended user guide. The existing
staged build now excludes it alongside `AGENTS.md` and checks generated pages,
search, sitemap and LLM indexes for either internal filename. The final search
no longer includes the glossary.

`tools/build-pkgdown.R` completed successfully, including installed-package
examples, all offline articles, reference/link checks and the internal-file
exclusion check. The GitHub workflow still builds PRs without deployment and
publishes `docs/` to `gh-pages` on its existing non-PR triggers. Search navigation
confirmed that the existing published reuse-guide URL remains valid.

This is a local implementation review. PR CI and verification of the refreshed
published site remain required after publication and an authorized merge.
