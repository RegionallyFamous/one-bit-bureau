# Bureau Inspector component contract

`InspectorPanel.qml` is a hosted `PanelWindow` intended to be instantiated once by `Experience.qml`. Services resolve live desktop, application, and window state; the Inspector remains a bounded view that emits intent.

Open it with:

```qml
inspector.openContext({
  kind: "app",
  id: "org.example.App",
  name: "Example",
  subtitle: "2 windows",
  iconSource: "image://icon/org.example.App",
  iconGrayscale: true,
  stale: false,
  missing: false,
  facts: [
    { id: "windows", label: "Windows", value: "2" }
  ],
  actions: [
    { id: "focus", label: "Focus recent window", enabled: true },
    { id: "close", label: "Close", enabled: false, reason: "No window is open" }
  ]
}, invokingScreen, Qt.point(pointerX, pointerY))
```

The component accepts at most 12 facts and 12 actions. It strips control characters, bounds display strings, accepts only local absolute paths plus `file://`, `image://`, and `qrc:/` icon sources, rejects malformed action identifiers, disables actions for missing objects, and drops unrecognized fields. Destructive actions require a second activation within four seconds. Route `actionRequested(action, context)` by the allow-listed action and stable `context.kind` plus `context.id`; never execute display text or a path supplied in the payload.

Set `reducedMotion` from the plugin's existing motion setting. `closed()` fires after Escape, the Close button, outside dismissal, or an explicit `close()` call. `returnFocusItem` is optional and restores focus when available.
