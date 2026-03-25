# Android App Optimization Backlog

Date: 2026-03-25

Scope: `D:\Dumb Panel\android-app`

Goal: make the Flutter App align with the panel's core workflows so mobile usage feels complete instead of "view-only plus a few shortcuts".

## Priority

### P1 In Progress

1. Task form parity
   Current gap: the App task form only supports basic fields, while the panel already supports task type, labels, retry interval, random delay, notification controls, dependency task, hook scripts, and multiple-instance behavior.
   Target: App can create and edit tasks with the same main configuration surface as the panel.
   Status: main configuration fields have now been added in the App; remaining work is deeper parity such as cron parsing/templates and later workflow linkage from scripts.

2. Task list management parity
   Current gap: the App list exposes run, stop, edit, delete, but still lacks enable/disable and stronger filtering/quick actions.
   Target: App task list supports high-frequency management actions without forcing users back to the panel.
   Status: status filters, enable/disable, copy, pin/unpin, richer task metadata, and clearer status presentation have now been added; remaining work is batch operations and deeper log-file management.

### P2 Pending

3. Script workspace parity
   Current gap: upload, create file/folder, and edit are available, but rename, delete, version history, rollback, formatting, download, and add-to-task are still missing.
   Target: scripts page behaves like a real mobile script workspace.
   Status: rename, delete, version history, rollback, formatting, and add-to-task have now been added; remaining work is move/copy, download, and deeper debug-run parity.

4. Backup and restore parity
   Current gap: the App can create, list, restore, and delete local backups, but still lacks import, download, backup selection, and restore progress.
   Target: backup flow matches panel semantics and visible progress.
   Status: import/upload, download, selectable backup content, encrypted-restore password prompts, and restore progress polling with source/selection display have now been added.

5. Dependency management parity
   Current gap: install/reinstall/delete/log view exists, but mirror settings and cancel install are still missing.
   Target: App can handle slow or stuck dependency installs with the same operational tools as the panel.
   Status: string-based dependency status parsing, batch uninstall, force uninstall, cancel-in-progress, mirror settings, and multi-name install submission have now been added.

6. Log center parity
   Current gap: search and stream view exist, but log cleanup and richer management actions are still missing.
   Target: App logs page supports both browsing and maintenance.
   Status: task-id/status filtering, auto refresh for running logs, per-log delete, batch delete, and retention-based log cleanup have now been added.

### P3 Pending

7. Security, users, and Open API polish
   Current gap: these sections are usable, but still lighter than the panel in filtering, operational detail, and management ergonomics.
   Target: complete the "admin-on-mobile" experience after the high-frequency workflows are closed.
   Status: users page now supports role adjustment and self-protection ergonomics, Open API create/edit now uses scope selection plus rate-limit configuration, and security page now supports login-log filtering/cleanup plus confirmed session revocation.

## Progress

- 2026-03-25: backlog created from app-vs-panel audit.
- 2026-03-25: started P1 implementation with task form and task list.
- 2026-03-25: task form now supports task type, labels, retry interval, random delay mode, notification settings, dependency task ID, hook scripts, and multiple-instance behavior.
- 2026-03-25: task list now supports status filters, enable/disable, copy task, pin/unpin, and richer card metadata closer to the panel.
- 2026-03-25: scripts page now supports file or directory rename/delete from the tree, directory-scoped upload/create actions, file add-to-task, in-editor formatting, and version history rollback.
- 2026-03-25: backup page now supports importing backup files, downloading backups, choosing backup selection when creating backups, encrypted restore password prompts, and in-page restore progress display with source and selection context.
- 2026-03-25: dependency page now supports panel-style string status parsing, multi-name install input, cancel in-progress installs, mirror configuration, batch uninstall, and force uninstall actions.
- 2026-03-25: log page now supports task-id and status filters, auto refresh for running logs, single and batch delete, and retention-based cleanup actions closer to the panel.
- 2026-03-25: users page now supports safer role management and current-user protection, Open API page now uses selectable scopes and rate-limit editing closer to the panel, and security page now supports login-log filtering/cleanup plus confirmed session revocation.
