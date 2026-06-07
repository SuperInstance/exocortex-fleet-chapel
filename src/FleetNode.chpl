// FleetNode.chpl — Device representation for the exocortex fleet
// Part of the ExocortexFleet distributed coordination system
//
// A FleetNode represents a single device in the fleet — a GPU server,
// a CPU worker, a microcontroller, or even a browser tab. Each node
// advertises capabilities and tracks its own load so the task scheduler
// can make informed placement decisions.
//
// Design note: FleetNode is a *record* (value type) because nodes are
// frequently copied into messages, task assignments, and health reports.
// The identity of a node lives in its `id` field, not in its heap address.

module FleetNode {

  /// The kinds of devices that participate in the fleet.
  /// The enum is exhaustive today; new device types (FPGA, TPU, NPU)
  /// can be added without breaking existing code because Chapel enums
  /// are open to extension at the module level.
  enum NodeType {
    GPU,             // Discrete or integrated GPU
    CPU,             // General-purpose CPU core/cluster
    Microcontroller, // Edge device: ESP32, RP2040, etc.
    Browser          // In-browser WASM runtime
  }

  /// A single device in the fleet.
  ///
  /// Fields are deliberately flat — no nested classes, no heap
  /// indirection beyond the string fields. This makes serialization
  /// trivial and copies cheap.
  record FleetNode {
    var id: string;
    var node_type: NodeType;
    var capabilities: domain(string);   // e.g. "inference", "training", "sensing"
    var load: real(64);                 // 0.0 … 1.0 (fraction of capacity in use)
    var latency_ms: real(64);          // round-trip latency estimate

    /// Does this node advertise the given capability?
    proc can_handle(task_type: string): bool {
      return capabilities.contains(task_type);
    }

    /// Current utilization as a 0–1 fraction.
    /// Clamps to [0, 1] for safety.
    proc utilization(): real(64) {
      return max(0.0, min(1.0, load));
    }

    /// Suitability score for a task of the given type.
    ///
    /// The score blends three factors:
    ///   - capability match  (binary: 1 if the node can do it, 0 otherwise)
    ///   - available capacity (1 − load)
    ///   - latency penalty    (lower is better)
    ///
    /// Result is in [0, 1]. A node that can't handle the task scores 0.
    proc score(task_type: string): real(64) {
      if !can_handle(task_type) then return 0.0;

      const capMatch = 1.0;
      const available = 1.0 - utilization();
      // Normalize latency: assume 200ms is "bad" and 0ms is "perfect"
      const latencyScore = max(0.0, 1.0 - (latency_ms / 200.0));

      // Weighted blend: capability is a gate, the rest is tradeoff
      return capMatch * (0.5 * available + 0.5 * latencyScore);
    }

    /// Serialize to a human-readable (JSON-like) string.
    /// Not strict JSON — just structured text for debugging.
    proc serialize(): string {
      var caps_str = "[";
      var first = true;
      for cap in capabilities {
        if !first then caps_str += ", ";
        caps_str += cap;
        first = false;
      }
      caps_str += "]";

      return "{id: " + id +
             ", type: " + node_type:string +
             ", capabilities: " + caps_str +
             ", load: " + load:string +
             ", latency_ms: " + latency_ms:string + "}";
    }
  }

} // module FleetNode
