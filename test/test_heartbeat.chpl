// test_heartbeat.chpl — Tests for the Heartbeat module
use Heartbeat;

proc main() {
  writeln("=== Heartbeat Tests ===");
  var passed = 0;
  var total = 0;

  // Test 1: Register nodes
  total += 1;
  var mon = new HeartbeatMonitor(threshold_ms = 5000.0);
  mon.register("gpu-0");
  mon.register("cpu-0");
  mon.register("mcu-0");
  assert(mon.node_count == 3);
  writeln("  PASS: Register 3 nodes");
  passed += 1;

  // Test 2: Duplicate registration is no-op
  total += 1;
  mon.register("gpu-0");
  assert(mon.node_count == 3);
  writeln("  PASS: Duplicate register no-op");
  passed += 1;

  // Test 3: Ping updates heartbeat
  total += 1;
  mon.ping("gpu-0", 1000.0);
  assert(mon.get_status("gpu-0", 1000.0) == HealthStatus.Healthy);
  writeln("  PASS: Ping updates heartbeat");
  passed += 1;

  // Test 4: Healthy within threshold
  total += 1;
  mon.ping("cpu-0", 1000.0);
  assert(mon.get_status("cpu-0", 2000.0) == HealthStatus.Healthy);
  writeln("  PASS: Healthy within threshold");
  passed += 1;

  // Test 5: Degraded at 60% of threshold
  total += 1;
  // threshold=5000, 60% = 3000. Ping at 1000, check at 4500 → elapsed=3500 > 3000
  mon.ping("mcu-0", 1000.0);
  assert(mon.get_status("mcu-0", 4500.0) == HealthStatus.Degraded);
  writeln("  PASS: Degraded at 60% threshold");
  passed += 1;

  // Test 6: Unreachable beyond threshold
  total += 1;
  mon.ping("cpu-0", 1000.0);
  assert(mon.get_status("cpu-0", 7000.0) == HealthStatus.Unreachable);
  writeln("  PASS: Unreachable beyond threshold");
  passed += 1;

  // Test 7: Unknown for unregistered node
  total += 1;
  assert(mon.get_status("phantom", 1000.0) == HealthStatus.Unknown);
  writeln("  PASS: Unknown for unregistered");
  passed += 1;

  // Test 8: Fleet health score — all healthy
  total += 1;
  var mon2 = new HeartbeatMonitor(threshold_ms = 5000.0);
  mon2.register("a");
  mon2.register("b");
  mon2.ping("a", 1000.0);
  mon2.ping("b", 1000.0);
  const score = mon2.fleet_health_score(1500.0);
  assert(score == 1.0);
  writeln("  PASS: Fleet health all healthy = 1.0");
  passed += 1;

  // Test 9: Fleet health score — mixed
  total += 1;
  var mon3 = new HeartbeatMonitor(threshold_ms = 5000.0);
  mon3.register("h1");
  mon3.register("h2");
  mon3.register("d1");
  mon3.register("u1");
  mon3.ping("h1", 1000.0);
  mon3.ping("h2", 1000.0);
  mon3.ping("d1", 1000.0);
  // h1,h2 healthy at t=1500, d1 degraded at t=4500, u1 never pinged
  const score2 = mon3.fleet_health_score(4500.0);
  // h1=1.0, h2=1.0, d1=0.5 (degraded), u1=0.0 (unknown)
  // total = 2.5 / 4 = 0.625
  assert(score2 == 0.625);
  writeln("  PASS: Fleet health mixed = ", score2);
  passed += 1;

  // Test 10: check_health summary
  total += 1;
  var mon4 = new HeartbeatMonitor(threshold_ms = 5000.0);
  mon4.register("n1");
  mon4.register("n2");
  mon4.ping("n1", 1000.0);
  mon4.ping("n2", 1000.0);
  const summary = mon4.check_health(1500.0);
  // Both healthy
  assert(summary[0].find("healthy:2") >= 0);
  assert(summary[1].find("degraded:0") >= 0);
  assert(summary[2].find("unreachable:0") >= 0);
  writeln("  PASS: check_health summary");
  passed += 1;

  // Test 11: Empty monitor has 0 health score
  total += 1;
  var mon5 = new HeartbeatMonitor(threshold_ms = 5000.0);
  assert(mon5.fleet_health_score(1000.0) == 0.0);
  writeln("  PASS: Empty monitor health = 0.0");
  passed += 1;

  writeln("\n  Heartbeat: ", passed, "/", total, " tests passed");
  assert(passed == total);
}
