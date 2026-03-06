# Changelog – Community Fork Patchset

## 2026-03-05
- Added NUI-ready handshake + JS resource name fallback to avoid init race issues.
- Reduced idle client loop work when lidar weapon is not selected.
- Made oxmysql optional (no manifest dependency); guarded all SQL calls and added wait-for-ready behavior.
- Batched SQL inserts to reduce database load.
