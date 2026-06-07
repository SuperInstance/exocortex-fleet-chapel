// test_fleet_node.chpl — Tests for the FleetNode module
use FleetNode;

proc main() {
  writeln("=== FleetNode Tests ===");
  var passed = 0;
  var total = 0;

  // Test 1: Create a GPU node
  total += 1;
  var gpu = new FleetNode(id = "gpu-0", node_type = NodeType.GPU,
                           load = 0.5, latency_ms = 10.0);
  gpu.capabilities.add("inference");
  gpu.capabilities.add("training");
  assert(gpu.id == "gpu-0");
  assert(gpu.node_type == NodeType.GPU);
  writeln("  PASS: Create GPU node");
  passed += 1;

  // Test 2: can_handle
  total += 1;
  assert(gpu.can_handle("inference") == true);
  assert(gpu.can_handle("sensing") == false);
  writeln("  PASS: can_handle");
  passed += 1;

  // Test 3: utilization
  total += 1;
  assert(gpu.utilization() == 0.5);
  writeln("  PASS: utilization");
  passed += 1;

  // Test 4: utilization clamps to [0, 1]
  total += 1;
  var overloaded = new FleetNode(id = "ov", node_type = NodeType.CPU,
                                  load = 2.0, latency_ms = 5.0);
  assert(overloaded.utilization() == 1.0);
  var underloaded = new FleetNode(id = "ul", node_type = NodeType.CPU,
                                   load = -0.5, latency_ms = 5.0);
  assert(underloaded.utilization() == 0.0);
  writeln("  PASS: utilization clamps");
  passed += 1;

  // Test 5: score for capable task
  total += 1;
  const s = gpu.score("inference");
  assert(s > 0.0);
  assert(s <= 1.0);
  writeln("  PASS: score for capable task = ", s);
  passed += 1;

  // Test 6: score for incapable task
  total += 1;
  assert(gpu.score("sensing") == 0.0);
  writeln("  PASS: score for incapable task");
  passed += 1;

  // Test 7: serialize
  total += 1;
  const ser = gpu.serialize();
  assert(ser.find("gpu-0") >= 0);
  assert(ser.find("GPU") >= 0);
  writeln("  PASS: serialize");
  passed += 1;

  // Test 8: Create microcontroller node
  total += 1;
  var mcu = new FleetNode(id = "mcu-sensor-0", node_type = NodeType.Microcontroller,
                           load = 0.1, latency_ms = 150.0);
  mcu.capabilities.add("sensing");
  mcu.capabilities.add("actuation");
  assert(mcu.node_type == NodeType.Microcontroller);
  assert(mcu.can_handle("sensing"));
  assert(!gpu.can_handle("sensing"));
  writeln("  PASS: Microcontroller node");
  passed += 1;

  // Test 9: Browser node type
  total += 1;
  var browser = new FleetNode(id = "tab-0", node_type = NodeType.Browser,
                               load = 0.0, latency_ms = 50.0);
  browser.capabilities.add("inference");
  assert(browser.node_type == NodeType.Browser);
  assert(browser.utilization() == 0.0);
  writeln("  PASS: Browser node");
  passed += 1;

  // Test 10: Low-latency node scores higher than high-latency
  total += 1;
  var fast_gpu = new FleetNode(id = "fast", node_type = NodeType.GPU,
                                load = 0.5, latency_ms = 1.0);
  fast_gpu.capabilities.add("inference");
  var slow_gpu = new FleetNode(id = "slow", node_type = NodeType.GPU,
                                load = 0.5, latency_ms = 199.0);
  slow_gpu.capabilities.add("inference");
  assert(fast_gpu.score("inference") > slow_gpu.score("inference"));
  writeln("  PASS: Latency affects score");
  passed += 1;

  writeln("\n  FleetNode: ", passed, "/", total, " tests passed");
  assert(passed == total);
}
