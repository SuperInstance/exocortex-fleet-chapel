// test_topology.chpl — Tests for the Topology module
use Topology;

proc main() {
  writeln("=== Topology Tests ===");
  var passed = 0;
  var total = 0;

  // Test 1: Add nodes via edges
  total += 1;
  var topo = new FleetTopology();
  topo.add_edge("a", "b", 1.0);
  topo.add_edge("b", "c", 2.0);
  assert(topo.node_count == 3);
  writeln("  PASS: Add nodes via edges");
  passed += 1;

  // Test 2: Neighbors
  total += 1;
  const nbrs = topo.neighbors("a");
  assert(nbrs[0] == "b");
  assert(nbrs[1] == ""); // only one neighbor
  writeln("  PASS: Neighbors");
  passed += 1;

  // Test 3: Shortest path — direct
  total += 1;
  topo.add_edge("c", "d", 3.0);
  const path_ab = topo.shortest_path("a", "b");
  assert(path_ab[0] == "a");
  assert(path_ab[1] == "b");
  writeln("  PASS: Shortest path direct");
  passed += 1;

  // Test 4: Shortest path — multi-hop
  total += 1;
  const path_ad = topo.shortest_path("a", "d");
  assert(path_ad[0] == "a");
  assert(path_ad[1] == "b");
  assert(path_ad[2] == "c");
  assert(path_ad[3] == "d");
  writeln("  PASS: Shortest path multi-hop");
  passed += 1;

  // Test 5: No path returns empty
  total += 1;
  topo.add_edge("x", "y", 1.0); // disconnected component
  const path_nx = topo.shortest_path("a", "x");
  assert(path_nx[0] == "");
  writeln("  PASS: No path returns empty");
  passed += 1;

  // Test 6: Self-path
  total += 1;
  const self_path = topo.shortest_path("a", "a");
  assert(self_path[0] == "a");
  writeln("  PASS: Self-path");
  passed += 1;

  // Test 7: is_connected — disconnected graph
  total += 1;
  assert(!topo.is_connected()); // x-y is disconnected from a-b-c-d
  writeln("  PASS: is_connected false");
  passed += 1;

  // Test 8: is_connected — connected graph
  total += 1;
  var topo2 = new FleetTopology();
  topo2.add_undirected("p", "q", 1.0);
  topo2.add_undirected("q", "r", 1.0);
  assert(topo2.is_connected());
  writeln("  PASS: is_connected true");
  passed += 1;

  // Test 9: connected_components
  total += 1;
  var topo3 = new FleetTopology();
  topo3.add_edge("a", "b", 1.0);
  topo3.add_edge("b", "c", 1.0);
  topo3.add_edge("x", "y", 1.0);
  const components = topo3.connected_components();
  // Should have two groups separated by ""
  var separators = 0;
  for i in 0..components.size-1 {
    if components[i] == "" then separators += 1;
  }
  assert(separators == 2);
  writeln("  PASS: connected_components finds 2 groups");
  passed += 1;

  // Test 10: Single node is connected
  total += 1;
  var topo4 = new FleetTopology();
  topo4.ensure_node("solo");
  assert(topo4.is_connected());
  writeln("  PASS: Single node is connected");
  passed += 1;

  // Test 11: Undirected edge adds both directions
  total += 1;
  var topo5 = new FleetTopology();
  topo5.add_undirected("m", "n", 5.0);
  const nbrs_m = topo5.neighbors("m");
  const nbrs_n = topo5.neighbors("n");
  assert(nbrs_m[0] == "n");
  assert(nbrs_n[0] == "m");
  writeln("  PASS: Undirected edge both directions");
  passed += 1;

  writeln("\n  Topology: ", passed, "/", total, " tests passed");
  assert(passed == total);
}
