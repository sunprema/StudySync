// Reading Journal — StudySync Direction 01: Margin Notes
// Data arrives via elixir_data injected by Imprintor.
//
// Fonts: place TTF/OTF files in priv/typst/fonts/ and pass them via
// Imprintor.Config extra_fonts for the full branded typeface.
// Falls back to Typst's bundled Libertinus Serif + DejaVu Sans Mono.

// ── Numeric coercion (must be first) ─────────────────────────────────────────
#let to-num(v) = {
  if v == none { none }
  else if type(v) == int { v }
  else if type(v) == float { v }
  else if type(v) == str {
    if v == "nil" or v == "" { none }
    else {
      let f = float(v)
      if f != none { f } else { int(v) }
    }
  }
  else { none }
}

// ── Palette ───────────────────────────────────────────────────────────────────
#let paper       = rgb("#F4EFE3")
#let paper-2     = rgb("#E8E0CE")
#let terracotta  = rgb("#B8512E")
#let ink         = rgb("#2A2521")
#let ink-soft    = rgb("#5C5750")
#let peach-bg    = rgb("#F5DDD1")
#let mint-bg     = rgb("#D1ECD7")
#let lavender-bg = rgb("#DDD1EC")
#let butter-bg   = rgb("#F5EDD1")

#let annotation-bg(color-name) = {
  if color-name == "peach"    { peach-bg }
  else if color-name == "mint"     { mint-bg }
  else if color-name == "lavender" { lavender-bg }
  else if color-name == "butter"   { butter-bg }
  else { paper-2 }
}

#let type-label(t) = {
  if t == "comment"  { "COMMENT" }
  else if t == "question" { "QUESTION" }
  else if t == "puzzle"   { "PUZZLE" }
  else { upper(str(t)) }
}

// ── Font helpers (override names if custom fonts are loaded) ──────────────────
#let font-display = "Libertinus Serif"
#let font-body    = "Libertinus Serif"
#let font-mono    = "DejaVu Sans Mono"

// ── Page setup ────────────────────────────────────────────────────────────────
#set page(
  paper: "a4",
  margin: (top: 2.5cm, bottom: 2.5cm, left: 2.8cm, right: 2.8cm),
  fill: paper,
  footer: context {
    let p = here().page()
    if p > 1 [
      #set text(font: font-mono, size: 7.5pt, fill: ink-soft)
      #grid(
        columns: (1fr, 1fr),
        align(left)[STUDYSYNC · READING JOURNAL],
        align(right)[#str(p - 1)]
      )
    ]
  }
)

#set text(font: font-body, size: 11pt, fill: ink)
#set par(leading: 0.65em, justify: true)

// ── Cover page ────────────────────────────────────────────────────────────────
#page(fill: paper, footer: none)[
  #v(4cm)
  #align(center)[
    #text(font: font-mono, size: 9pt, fill: ink-soft)[READING JOURNAL]

    #v(1.2cm)

    #text(font: font-display, size: 30pt, fill: ink)[
      #elixir_data.book_title
    ]

    #v(2.4cm)

    #line(length: 6cm, stroke: 0.5pt + terracotta)

    #v(1.2cm)

    #text(font: font-mono, size: 8.5pt, fill: ink-soft)[
      #upper[#elixir_data.reader_email]
    ]

    #v(0.5cm)

    #text(font: font-mono, size: 8.5pt, fill: ink-soft)[
      EXPORTED · #upper[#elixir_data.exported_at]
    ]

    #v(0.5cm)

    #let n = to-num(elixir_data.annotation_count)
    #let count-str = if n == none { "—" } else { str(int(n)) }
    #let noun = if n == 1 { "ANNOTATION" } else { "ANNOTATIONS" }

    #text(font: font-mono, size: 8.5pt, fill: ink-soft)[
      #count-str #noun
    ]
  ]
]

// ── Reply card ────────────────────────────────────────────────────────────────
#let reply-card(reply) = {
  let raw-is-ai = reply.at("is_ai_response", default: "false")
  let is-ai = if type(raw-is-ai) == bool { raw-is-ai }
              else { str(raw-is-ai) == "true" }
  let bg = if is-ai { butter-bg } else { paper }
  let author = if is-ai { "AI" } else {
    let email = str(reply.at("user_email", default: "—"))
    let parts = email.split("@")
    if parts.len() > 0 { upper(parts.at(0)) } else { "—" }
  }
  let ts = str(reply.at("inserted_at", default: ""))

  block(
    width: 100%,
    fill: bg,
    inset: (x: 10pt, y: 7pt),
    radius: 3pt,
    [
      #grid(
        columns: (auto, 1fr),
        column-gutter: 8pt,
        [
          #if is-ai [
            #text(font: font-mono, size: 7.5pt, fill: terracotta)[AI]
          ] else [
            #text(font: font-mono, size: 7.5pt, fill: ink-soft)[#author]
          ]
        ],
        align(right)[
          #text(font: font-mono, size: 7.5pt, fill: ink-soft)[#ts]
        ]
      )
      #v(4pt)
      #text(size: 10pt)[#str(reply.at("body", default: ""))]
    ]
  )
}

// ── Annotation card ───────────────────────────────────────────────────────────
#let annotation-card(ann) = {
  let color-name  = str(ann.at("color", default: "peach"))
  let ann-type    = str(ann.at("type", default: "comment"))
  let passage     = str(ann.at("text", default: ""))
  let body        = str(ann.at("body", default: ""))
  let replies     = ann.at("replies", default: ())
  let ts          = str(ann.at("inserted_at", default: ""))
  let bg          = annotation-bg(color-name)

  block(width: 100%, breakable: false)[
    // Type badge + timestamp row
    #grid(
      columns: (1fr, auto),
      [
        #text(font: font-mono, size: 7.5pt, fill: terracotta)[
          #type-label(ann-type)
        ]
      ],
      [
        #text(font: font-mono, size: 7.5pt, fill: ink-soft)[#ts]
      ]
    )

    #v(6pt)

    // Captured passage as block quote
    #if passage != "" [
      #block(
        width: 100%,
        fill: bg,
        inset: (left: 14pt, right: 10pt, top: 8pt, bottom: 8pt),
        radius: (right: 3pt),
        stroke: (left: 2.5pt + terracotta),
      )[
        #text(size: 10.5pt, style: "italic")[#passage]
      ]
      #v(6pt)
    ]

    // Annotation body note
    #if body != "" [
      #text(size: 11pt)[#body]
      #v(6pt)
    ]

    // Thread replies
    #if replies.len() > 0 [
      #v(2pt)
      #for reply in replies [
        #reply-card(reply)
        #v(4pt)
      ]
    ]
  ]
}

// ── Body: one section per annotated page ─────────────────────────────────────
#for page-group in elixir_data.pages [
  #let pnum = page-group.at("page_number", default: 0)
  #let anns = page-group.at("annotations", default: ())

  #v(0.8cm)

  // Page section header
  #block(width: 100%, below: 12pt)[
    #grid(
      columns: (auto, 1fr),
      column-gutter: 12pt,
      align: bottom,
      [
        #text(font: font-display, size: 22pt, fill: terracotta)[
          #str(pnum)
        ]
      ],
      [
        #line(length: 100%, stroke: 0.5pt + ink-soft)
        #v(3pt)
        #let note-noun = if anns.len() == 1 { "NOTE" } else { "NOTES" }
        #text(font: font-mono, size: 7.5pt, fill: ink-soft)[
          PAGE · #str(anns.len()) #note-noun
        ]
      ]
    )
  ]

  // Annotations for this page
  #for ann in anns [
    #annotation-card(ann)
    #v(14pt)
  ]

  #v(0.4cm)
]
