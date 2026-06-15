# Type Safety

> Type safety patterns in this project.

## Scenario: Panel API defaults and runtime-mode payloads

### 1. Scope / Trigger

- Trigger: Flutter screens consume panel APIs whose payloads contain backend-owned defaults or runtime-mode metadata.
- Examples in this repo:
  - `GET /api/deps/python-runtimes`
  - `GET /api/system/check-update`
  - `GET /api/system/update-status`

### 2. Signatures

- `GET /api/deps/python-runtimes`
  - Response shape:
    - `data: PythonRuntimeInfo[]`
    - `default_version: string`
- `GET /api/system/check-update`
  - Response shape:
    - `data.current: string`
    - `data.latest: string`
    - `data.has_update: bool`
    - `data.auto_update_supported: bool`
    - `data.update_disabled_reason: string`
    - `data.update_target: map`
- `GET /api/system/update-status`
  - Response shape:
    - `data.status: string`
    - `data.phase: string`
    - `data.message: string`
    - `data.error: string`

### 3. Contracts

- Backend defaults must be read from payloads, not copied into UI constants.
- Shared payload models belong in `lib/shared/models/` when more than one feature reads the same response shape.
- UI code may provide fallback values only as a last-resort compatibility guard when the backend field is absent.
- Runtime-mode payloads such as `update_target` must be rendered by mode:
  - `deployment_type = binary`
  - `update_manager = watchtower`
  - default Docker update path

### 4. Validation & Error Matrix

- Missing `default_version`:
  - UI may fallback to `'3.12'`, but must still prefer backend value whenever present.
- Missing or partial `data` list:
  - UI must not crash; show fallback dropdown items or read-only status text.
- Unknown `update_target` fields:
  - UI must keep a generic status summary instead of assuming one update flow.
- `auto_update_supported = false`:
  - UI must disable or hide the immediate update action and show the backend reason text.

### 5. Good / Base / Bad Cases

- Good:
  - Task-create page reads `default_version` and uses it as the new-task Python default.
  - Update page switches button text and success hint based on `update_target`.
- Base:
  - Backend omits optional fields, UI still renders a safe fallback summary.
- Bad:
  - Hardcoding `3.12` as the create-task default after the panel already supports configurable default runtimes.
  - Always showing “panel will auto restart” even when the backend is using Watchtower manual trigger flow.

### 6. Tests Required

- Widget or integration coverage should assert:
  - New-task form uses backend `default_version` when available.
  - Existing-task edit form does not overwrite the stored Python version.
  - Update UI changes label / hint when `update_target.update_manager == watchtower`.
  - Update UI renders a generic safe message when `update_target` is missing fields.

### 7. Wrong vs Correct

#### Wrong

```dart
String _pythonVersion = '3.12';
```

```dart
showSnackBar('更新已启动，面板将自动重启');
```

#### Correct

```dart
// 新建任务默认值优先以后端返回为准，避免和面板设置漂移。
_pythonVersion = defaultVersionFromApi;
```

```dart
if (isWatchtowerManaged) {
  showSnackBar('已触发 Watchtower 检查更新，请稍后查看结果');
} else if (isBinaryUpdate) {
  showSnackBar('后台更新任务已启动，面板完成替换后会自动重启');
}
```

## Common Patterns

- Parse transport payloads with small shared model classes instead of repeating inline `Map` extraction in multiple screens.
- Keep backend compatibility fallbacks close to the boundary code that reads the response.

## Forbidden Patterns

- Do not hardcode backend-owned defaults in forms when an API already exposes the real default.
- Do not collapse distinct backend runtime modes into a single user-facing status sentence.
