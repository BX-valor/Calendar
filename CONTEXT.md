# ConferenceDeadline Context

This document defines the ubiquitous language for the ConferenceDeadline app.

## Glossary

### Conference
An academic conference the user wants to track, such as NeurIPS, CVPR, or ACM MM.

### Deadline
A key point in time during a conference's submission lifecycle.

- **Abstract Deadline** — The deadline for registering or submitting an abstract.
- **Paper Deadline** — The deadline for submitting the full paper.
- **Rebuttal Deadline** — The deadline for authors to respond to reviewer comments. Optional.
- **Final Decision Date** — The date authors are notified of acceptance or rejection. Optional.
- **Conference Date** — The date the conference actually takes place. Optional.

### Category
The academic domain a conference belongs to, e.g. `ML`, `CV`, `NLP`, `MM`, `DM`, `IR`.

### Tag
An additional label attached to a conference. Tags are free-form but every conference must include a CCF rating tag.

- **CCF Rating Tag** — One of `CCF-A`, `CCF-B`, or `CCF-C`, based on the China Computer Federation recommended ranking.
- **Predefined Tags** — `CCF-A`, `CCF-B`, `CCF-C`, `国内`, `顶会`, `推荐`.
- **Custom Tag** — Any user-defined string.

### Location
The city and country where the conference is held, e.g. `Seoul, South Korea`. Optional.

### Venue
The specific venue or building where the conference is held, e.g. `COEX Convention Center`. Optional.

### Timezone
The timezone used for deadlines. If not specified, deadlines are interpreted as **AoE (Anywhere on Earth, UTC-12)**.

### Default Conference
A conference shipped with the app in the built-in `conferences.json`.

### User Conference
A conference added or modified by the user, persisted to `~/Library/Application Support/ConferenceDeadline/userConferences.json`.
