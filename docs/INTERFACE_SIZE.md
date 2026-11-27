# Interface size

Settings → Appearance has two independent controls (stored per device):

* **Interface size** (50 %–130 %, default 90 %): scales the whole UI like browser zoom — text, icons, spacing and tap
  targets together. The app is laid out in a virtual viewport of `size / zoom` and painted scaled (`_UiZoom` in
  `lib/app/app.dart`); status-bar and keyboard insets are scaled to match, and dialogs/sheets/menus live inside the
  Navigator so they follow.
* **Text size** (70 %–150 %): text only.

The first-run Welcome dialog offers the same size presets (Tiny · Small · Compact · Standard · Large) with an
instant preview.
