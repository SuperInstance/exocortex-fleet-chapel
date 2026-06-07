// Topology.chpl — Fleet network topology for the exocortex
// Part of the ExocortexFleet distributed coordination system
//
// The FleetTopology module models the network graph of the fleet.
// Nodes are devices (identified by string ID), edges are network links
// with associated weights (latency, cost, etc.).
//
// All algorithms are iterative (no recursion) per project constraints.
// BFS is used for shortest path on unweighted graphs; for weighted
// paths we'd swap in Dijkstra or A*.

module Topology {

  /// Represents the network topology as an adjacency-list graph.
  ///
  /// Uses fixed-size arrays for simplicity. A production version
  /// would use Chapel's domain/map features for dynamic sizing.
  class FleetTopology {
    // Edge storage: adjacency list representation
    // Each node has a list of (neighbor, weight) pairs
    var node_ids: [0..#64] string;
    var node_count: int = 0;

    // Adjacency: edges[from_idx] = list of (to_idx, weight)
    var edge_targets: [0..#64, 0..#32] int;      // target node index
    var edge_weights: [0..#64, 0..#32] real(64);  // edge weight
    var edge_counts: [0..#64] int;                // edges per node

    // ── Node Management ───────────────────────────────────────────

    /// Add a node to the topology. Returns its index.
    proc ensure_node(node_id: string): int {
      for i in 0..#node_count {
        if node_ids[i] == node_id then return i;
      }
      if node_count < node_ids.size {
        node_ids[node_count] = node_id;
        edge_counts[node_count] = 0;
        node_count += 1;
        return node_count - 1;
      }
      return -1; // full
    }

    /// Find the index of a node, or -1.
    proc find_node(node_id: string): int {
      for i in 0..#node_count {
        if node_ids[i] == node_id then return i;
      }
      return -1;
    }

    // ── Edge Management ───────────────────────────────────────────

    /// Add a directed edge with a weight (latency, cost, etc.).
    proc add_edge(from_id: string, to_id: string, weight: real(64)) {
      const from_idx = ensure_node(from_id);
      const to_idx = ensure_node(to_id);
      if from_idx < 0 || to_idx < 0 then return;

      // Check if edge already exists (update weight)
      for j in 0..#edge_counts[from_idx] {
        if edge_targets[from_idx, j] == to_idx {
          edge_weights[from_idx, j] = weight;
          return;
        }
      }

      // Add new edge
      const cnt = edge_counts[from_idx];
      if cnt < edge_targets.dim(1).size {
        edge_targets[from_idx, cnt] = to_idx;
        edge_weights[from_idx, cnt] = weight;
        edge_counts[from_idx] += 1;
      }
    }

    /// Add an undirected edge (both directions).
    proc add_undirected(a_id: string, b_id: string, weight: real(64)) {
      add_edge(a_id, b_id, weight);
      add_edge(b_id, a_id, weight);
    }

    // ── Neighbors ─────────────────────────────────────────────────

    /// Get the neighbor IDs of a node.
    proc neighbors(node_id: string): [] string {
      const idx = find_node(node_id);
      var result: [0..#32] string;
      var count = 0;
      if idx >= 0 {
        for j in 0..#edge_counts[idx] {
          result[count] = node_ids[edge_targets[idx, j]];
          count += 1;
        }
      }
      // Return a properly-sized slice
      var out: [0..#max(1,count)] string;
      for i in 0..#count do out[i] = result[i];
      return out;
    }

    // ── Shortest Path (BFS) ───────────────────────────────────────

    /// Find the shortest path (fewest hops) between two nodes using BFS.
    ///
    /// Returns an array of node IDs forming the path, or an empty
    /// array if no path exists.
    ///
    /// BFS is appropriate here because fleet topology edges are
    /// typically similar weight (all network links). For weighted
    /// shortest path, swap in Dijkstra.
    proc shortest_path(from_id: string, to_id: string): [] string {
      const from_idx = find_node(from_id);
      const to_idx = find_node(to_id);

      // Sentinel: empty path
      var empty: [0..#1] string;
      empty[0] = "";
      if from_idx < 0 || to_idx < 0 then return empty;
      if from_idx == to_idx {
        var single: [0..#1] string;
        single[0] = from_id;
        return single;
      }

      // BFS state
      var visited: [0..#64] bool;
      var parent: [0..#64] int;
      for i in 0..#64 {
        visited[i] = false;
        parent[i] = -1;
      }

      // BFS queue (simple array-based)
      var queue: [0..#64] int;
      var q_head = 0;
      var q_tail = 0;

      queue[q_tail] = from_idx;
      q_tail += 1;
      visited[from_idx] = true;

      var found = false;

      // Iterative BFS
      while q_head < q_tail {
        const current = queue[q_head];
        q_head += 1;

        if current == to_idx {
          found = true;
          break;
        }

        // Explore neighbors
        for j in 0..#edge_counts[current] {
          const neighbor = edge_targets[current, j];
          if !visited[neighbor] {
            visited[neighbor] = true;
            parent[neighbor] = current;
            queue[q_tail] = neighbor;
            q_tail += 1;
          }
        }
      }

      if !found then return empty;

      // Reconstruct path iteratively
      var path_nodes: [0..#64] int;
      var path_len = 0;
      var cur = to_idx;
      while cur >= 0 {
        path_nodes[path_len] = cur;
        path_len += 1;
        cur = parent[cur];
      }

      // Reverse into output array
      var result: [0..#path_len] string;
      for i in 0..#path_len {
        result[i] = node_ids[path_nodes[path_len - 1 - i]];
      }
      return result;
    }

    // ── Connected Components ──────────────────────────────────────

    /// Find all connected components using iterative BFS.
    ///
    /// Returns a flat array where each component is terminated by
    /// an empty string. For example: ["a","b","","c","d",""] means
    /// two components {a,b} and {c,d}.
    proc connected_components(): [] string {
      var visited: [0..#64] bool;
      var result: [0..#256] string;
      var result_len = 0;

      for start in 0..#node_count {
        if visited[start] then continue;

        // BFS from this unvisited node
        var queue: [0..#64] int;
        var q_head = 0;
        var q_tail = 0;

        queue[q_tail] = start;
        q_tail += 1;
        visited[start] = true;

        while q_head < q_tail {
          const current = queue[q_head];
          q_head += 1;

          result[result_len] = node_ids[current];
          result_len += 1;

          for j in 0..#edge_counts[current] {
            const neighbor = edge_targets[current, j];
            if !visited[neighbor] {
              visited[neighbor] = true;
              queue[q_tail] = neighbor;
              q_tail += 1;
            }
          }
        }

        // Component separator
        result[result_len] = "";
        result_len += 1;
      }

      var out: [0..#max(1, result_len)] string;
      for i in 0..#result_len do out[i] = result[i];
      return out;
    }

    // ── Connectivity Check ────────────────────────────────────────

    /// Is the graph (ignoring edge direction) fully connected?
    /// Uses a single BFS from node 0 and checks if all nodes are reached.
    proc is_connected(): bool {
      if node_count <= 1 then return true;

      var visited: [0..#64] bool;
      var queue: [0..#64] int;
      var q_head = 0;
      var q_tail = 0;

      queue[q_tail] = 0;
      q_tail += 1;
      visited[0] = true;
      var visited_count = 1;

      while q_head < q_tail {
        const current = queue[q_head];
        q_head += 1;

        // Check outgoing edges
        for j in 0..#edge_counts[current] {
          const neighbor = edge_targets[current, j];
          if !visited[neighbor] {
            visited[neighbor] = true;
            visited_count += 1;
            queue[q_tail] = neighbor;
            q_tail += 1;
          }
        }

        // Check incoming edges (for undirected connectivity)
        for other in 0..#node_count {
          if visited[other] then continue;
          for j in 0..#edge_counts[other] {
            if edge_targets[other, j] == current {
              visited[other] = true;
              visited_count += 1;
              queue[q_tail] = other;
              q_tail += 1;
            }
          }
        }
      }

      return visited_count == node_count;
    }
  }

} // module Topology
