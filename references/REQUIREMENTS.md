# StudySync — REQUIREMENTS.md

## 1. Overview

StudySync is a **collaborative, AI-assisted study platform** centered around **PDF-based learning**.
Users can upload study materials, annotate them, discuss contextually, and track progress through **milestones and rubber stamps**.

The system is built with:

- **Backend / UI**: Elixir + Phoenix LiveView
- **Interactive UI Components**: Svelte 5 via Live Svelte
- **Database**: PostgreSQL
- **Background Jobs**: Oban
- **Styling**: Tailwind CSS
- **PDF Rendering**: PDF.js (via Svelte)

---

## 2. Core Product Principles

1. **PDF is the primary content unit**
2. **Annotations are first-class objects**
3. **All interactions are contextually anchored to the document**
4. **Real-time collaboration is default**
5. **AI augments, not replaces, human discussion**
6. **Progress tracking should be visible, social, and fun**

---

## 3. Core Features (MVP)

### 3.1 Workspaces

- Users can:
  - Create workspaces
  - Invite members
  - Assign roles (admin, member)

---

### 3.2 Resources (PDFs)

- Upload PDF files
- Store metadata:
  - title
  - workspace_id
  - file_url

- PDFs are rendered using PDF.js

---

### 3.3 PDF Reader (Margin Notes Layout)

#### Layout:

- Left: PDF Viewer
- Right: Margin Notes Panel

#### Requirements:

- Scrollable PDF
- Text selection enabled
- Highlight overlays rendered
- Annotation anchors displayed inline (footnote-style markers)

---

### 3.4 Annotations

#### Annotation Types:

- comment
- question
- puzzle
- ai_response

#### Properties:

- id
- resource_id
- page_number
- rect (x, y, width, height)
- text (selected content)
- user_id
- type
- color
- visibility (private | workspace)

---

### 3.5 Annotation Threads

- Each annotation has a thread of comments
- Comments can be:
  - user-generated
  - AI-generated

#### Properties:

- annotation_id
- user_id
- body
- is_ai_response (boolean)

---

### 3.6 Annotation Panel (Margin Notes)

- Displays annotations for current page
- Each annotation:
  - Shows author, timestamp
  - Displays selected text context
  - Supports replies

- Clicking annotation:
  - Scrolls PDF to location
  - Highlights text

---

### 3.7 Bi-Directional Sync

#### Required Behavior:

- Clicking annotation → scroll PDF
- Clicking PDF marker → scroll annotation panel
- Active annotation is highlighted in both views

---

### 3.8 Text Selection & Annotation Creation

#### Flow:

1. User selects text in PDF
2. Floating menu appears:
   - Add Comment
   - Ask AI
   - Create Puzzle

3. Selection event sent to LiveView
4. Annotation form appears in margin panel
5. On submit:
   - Annotation is saved
   - UI updates in real-time

---

### 3.9 AI Assistant

- Users can ask questions on selected text
- AI response is:
  - Stored as part of annotation thread
  - Marked as `is_ai_response = true`

#### Execution:

- Triggered via LiveView
- Processed via Oban background job

---

### 3.10 Milestone Markers (Rubber Stamp System)

#### Milestone Marker:

- Created by workspace admin
- Anchored to:
  - page_number
  - position (x, y)

- Represents a checkpoint (e.g., "Finished Chapter 1")

#### Rubber Stamp:

- Applied by users
- Indicates completion

#### Properties:

- milestone_id
- user_id
- timestamp
- optional note

---

### 3.11 Milestone Behavior

- Displayed on PDF as markers
- Clicking marker:
  - Shows completion state
  - Allows stamping

#### UI Requirements:

- Show progress: `X / N users completed`
- Display avatars of users who stamped

---

### 3.12 Real-Time Updates

- Use Phoenix PubSub
- Broadcast:
  - New annotations
  - New comments
  - New stamps

---

## 4. Component Architecture

### 4.1 LiveView Components

- PdfLive.Show (main page)
- PdfViewerLive
- AnnotationPanelLive
- AnnotationThreadLive
- MilestonePanelLive

---

### 4.2 Svelte Components (via Live Svelte)

Used ONLY for complex UI:

- PdfCanvasRenderer
  - PDF.js rendering
  - Text selection
  - Highlight overlays
  - Annotation markers
  - Milestone markers

---

## 5. LiveView ↔ Svelte Contract

### Props (LiveView → Svelte)

- annotations[]
- milestone_markers[]
- rubber_stamps[]
- active_annotation_id

---

### Events (Svelte → LiveView)

- text_selected
  - { text, page, rect }

- annotation_clicked
  - { id }

- apply_stamp
  - { milestone_id }

---

## 6. Data Model (Simplified)

### resources

- id
- workspace_id
- title
- file_url

### annotations

- id
- resource_id
- page_number
- rect (json)
- text
- user_id
- type
- color
- visibility

### annotation_comments

- id
- annotation_id
- user_id
- body
- is_ai_response

### milestone_markers

- id
- resource_id
- page_number
- position (json)
- label
- created_by

### rubber_stamps

- id
- milestone_id
- user_id
- note
- inserted_at

---

## 7. Performance Requirements

- Lazy load annotations per page
- Minimize LiveView re-renders
- Use Svelte for high-frequency DOM updates
- Optimize PDF rendering with page virtualization

---

## 8. UX Requirements

- Smooth scrolling between PDF and annotations
- Highlight animation on navigation
- Hover linking between PDF and margin notes
- Low-latency interactions (<100ms perceived delay)

---

## 9. Non-Goals (MVP)

- No mobile-first UI
- No video/audio annotations
- No offline support
- No external LMS integrations

---

## 10. Success Criteria

- Users can:
  - Upload PDF
  - Create annotations
  - See real-time updates
  - Ask AI questions
  - Apply milestone stamps

- Core loop works flawlessly:

  ```
  Read → Highlight → Annotate → Discuss → AI → Save → Progress
  ```

---

## 11. Future Extensions (Not Required Now)

- Flashcard generation
- Public resource marketplace
- Gamification (badges, leaderboards)
- Advanced analytics for educators

---

## 12. Implementation Priority

1. PDF Viewer + Text Selection
2. Annotation Creation + Display
3. Bi-directional Sync
4. Annotation Threads
5. AI Integration
6. Milestone + Rubber Stamp System

---

## Final Note

Coding agents should prioritize:

- **Correctness of annotation positioning**
- **Smooth interaction between PDF and margin panel**
- **Real-time consistency across users**

UX quality is critical. Even small latency or sync issues will degrade the experience significantly.
