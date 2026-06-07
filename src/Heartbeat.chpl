// Heartbeat.chpl — Fleet health monitoring for the exocortex
// Part of the ExocortexFleet distributed coordination system
//
// The HeartbeatMonitor tracks which nodes are alive, degraded, or
// unreachable based on periodic heartbeat messages. It's the fleet's
// equivalent of a watchdog timer — if a node stops pinging, we notice.
//
// In a real distributed system, each locale would run its own monitor
// and the monitors would gossip to reach a shared view. Here we model
// a single monitor for simplicity.

module Heartbeat {

  /// Health status of a fleet node.
  enum HealthStatus {
    Healthy,    // Recent heartbeat, low latency
    Degraded,   // Heartbeat present but late or high latency
    Unreachable,// No heartbeat within threshold
    Unknown     // Never registered or no data
  }

  /// Monitors the health of fleet nodes via heartbeat pings.
  class HeartbeatMonitor {
    var node_ids: [0..#128] string;
    var node_count: int = 0;
    var last_heartbeat: [0..#128] real(64);  // timestamp of last ping
    var avg_latency: [0..#128] real(64);      // rolling average latency
    var registered: [0..#128] bool;           // has this slot been registered?
    var threshold_ms: real(64);               // time without ping = unreachable

    proc init(threshold_ms: real(64) = 5000.0) {
      this.threshold_ms = threshold_ms;
    }

    // ── Registration ──────────────────────────────────────────────

    /// Register a new node for monitoring.
    proc register(node_id: string) {
      // Check if already registered
      for i in 0..#node_count {
        if node_ids[i] == node_id then return;
      }
      if node_count < node_ids.size {
        node_ids[node_count] = node_id;
        last_heartbeat[node_count] = 0.0;
        avg_latency[node_count] = 0.0;
        registered[node_count] = true;
        node_count += 1;
      }
    }

    // ── Heartbeat ─────────────────────────────────────────────────

    /// Record a heartbeat from a node at the given time.
    ///
    /// `timestamp` should be a monotonic clock value in milliseconds.
    /// We also compute a simple latency estimate from the gap between
    /// heartbeats.
    proc ping(node_id: string, timestamp: real(64)) {
      for i in 0..#node_count {
        if node_ids[i] == node_id {
          // Update rolling average latency (exponential moving average)
          if last_heartbeat[i] > 0.0 {
            const gap = timestamp - last_heartbeat[i];
            avg_latency[i] = 0.7 * avg_latency[i] + 0.3 * gap;
          }
          last_heartbeat[i] = timestamp;
          return;
        }
      }
    }

    // ── Health Check ──────────────────────────────────────────────

    /// Check the health of all registered nodes at the given `now` time.
    ///
    /// Returns arrays of node IDs and their health statuses.
    /// Uses iterative logic (no recursion) per project constraints.
    proc check_health(now: real(64)): [] string {
      // We return node IDs; status is queried per-node
      // (Chapel doesn't easily return tuples of arrays from procs)
      var healthy_count = 0;
      var degraded_count = 0;
      var unreachable_count = 0;

      for i in 0..#node_count {
        if !registered[i] then continue;
        const status = node_health(i, now);
        select status {
          when HealthStatus.Healthy do healthy_count += 1;
          when HealthStatus.Degraded do degraded_count += 1;
          when HealthStatus.Unreachable do unreachable_count += 1;
          otherwise do unreachable_count += 1;
        }
      }
      // Return a summary array: [healthy, degraded, unreachable] counts
      var result: [0..#3] string;
      result[0] = "healthy:" + healthy_count:string;
      result[1] = "degraded:" + degraded_count:string;
      result[2] = "unreachable:" + unreachable_count:string;
      return result;
    }

    /// Get the health status of a single node.
    proc node_health(idx: int, now: real(64)): HealthStatus {
      if !registered[idx] then return HealthStatus.Unknown;
      if last_heartbeat[idx] == 0.0 then return HealthStatus.Unknown;

      const elapsed = now - last_heartbeat[idx];
      if elapsed > threshold_ms then return HealthStatus.Unreachable;
      if elapsed > threshold_ms * 0.6 then return HealthStatus.Degraded;
      return HealthStatus.Healthy;
    }

    /// Get the health status of a node by ID.
    proc get_status(node_id: string, now: real(64)): HealthStatus {
      for i in 0..#node_count {
        if node_ids[i] == node_id then return node_health(i, now);
      }
      return HealthStatus.Unknown;
    }

    // ── Fleet Health ──────────────────────────────────────────────

    /// Overall fleet health score from 0.0 (all dead) to 1.0 (all healthy).
    ///
    /// Healthy = 1.0, Degraded = 0.5, Unreachable/Unknown = 0.0.
    /// Returns the average across all registered nodes.
    proc fleet_health_score(now: real(64)): real(64) {
      if node_count == 0 then return 0.0;

      var total: real(64) = 0.0;
      for i in 0..#node_count {
        if !registered[i] then continue;
        const status = node_health(i, now);
        select status {
          when HealthStatus.Healthy do total += 1.0;
          when HealthStatus.Degraded do total += 0.5;
          otherwise do total += 0.0;
        }
      }
      return total / node_count:real(64);
    }
  }

} // module Heartbeat
