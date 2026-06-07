// test_consensus.chpl — Tests for the Consensus module
use Consensus;

proc main() {
  writeln("=== Consensus Tests ===");
  var passed = 0;
  var total = 0;

  // Test 1: Create pool with nodes
  total += 1;
  var pool = new ConsensusPool();
  pool.add_node("node-a");
  pool.add_node("node-b");
  pool.add_node("node-c");
  assert(pool.node_count == 3);
  assert(pool.majority() == 2);
  writeln("  PASS: Create pool, majority=2");
  passed += 1;

  // Test 2: Start election
  total += 1;
  pool.start_election("node-a");
  assert(pool.state == ConsensusState.Candidate);
  assert(pool.current_term == 1);
  assert(pool.voted_for == "node-a");
  assert(pool.votes_received == 1);
  writeln("  PASS: Start election");
  passed += 1;

  // Test 3: Win election with majority votes
  total += 1;
  const accepted = pool.vote("node-b", 1);
  assert(accepted);
  assert(pool.state == ConsensusState.Leader);
  assert(pool.is_leader());
  writeln("  PASS: Win election");
  passed += 1;

  // Test 4: Leader can propose
  total += 1;
  const proposed = pool.propose("task-assignment: gpu-0 -> t1");
  assert(proposed);
  assert(pool.committed_count_val() == 1);
  writeln("  PASS: Leader proposes");
  passed += 1;

  // Test 5: Multiple proposals
  total += 1;
  pool.propose("rebalance fleet");
  pool.propose("rotate leader");
  assert(pool.committed_count_val() == 3);
  writeln("  PASS: Multiple proposals");
  passed += 1;

  // Test 6: Follower cannot propose
  total += 1;
  var pool2 = new ConsensusPool();
  pool2.add_node("x");
  pool2.add_node("y");
  assert(!pool2.is_leader());
  assert(!pool2.propose("should fail"));
  writeln("  PASS: Follower cannot propose");
  passed += 1;

  // Test 7: Reject vote for wrong term
  total += 1;
  var pool3 = new ConsensusPool();
  pool3.add_node("a");
  pool3.add_node("b");
  pool3.start_election("a");
  const wrong_term = pool3.vote("b", 999); // wrong term
  assert(!wrong_term);
  writeln("  PASS: Reject vote for wrong term");
  passed += 1;

  // Test 8: Step down on higher term
  total += 1;
  var pool4 = new ConsensusPool();
  pool4.add_node("a");
  pool4.add_node("b");
  pool4.add_node("c");
  pool4.start_election("a");
  pool4.vote("b", pool4.current_term);
  assert(pool4.is_leader());
  pool4.step_down(100);
  assert(pool4.state == ConsensusState.Follower);
  assert(!pool4.is_leader());
  assert(pool4.current_term == 100);
  writeln("  PASS: Step down on higher term");
  passed += 1;

  // Test 9: Step down ignores lower terms
  total += 1;
  var pool5 = new ConsensusPool();
  pool5.add_node("a");
  pool5.add_node("b");
  pool5.start_election("a");
  pool5.vote("b", pool5.current_term);
  assert(pool5.is_leader());
  pool5.step_down(0); // lower term, should be ignored
  assert(pool5.is_leader());
  writeln("  PASS: Step down ignores lower term");
  passed += 1;

  // Test 10: Five-node cluster needs 3 votes
  total += 1;
  var pool6 = new ConsensusPool();
  for i in 1..5 {
    pool6.add_node("n" + i:string);
  }
  assert(pool6.majority() == 3);
  pool6.start_election("n1"); // self-vote = 1
  assert(pool6.votes_received == 1);
  assert(pool6.state == ConsensusState.Candidate);
  pool6.vote("n2", pool6.current_term); // 2 votes
  assert(pool6.state == ConsensusState.Candidate); // not majority yet
  pool6.vote("n3", pool6.current_term); // 3 votes = majority
  assert(pool6.state == ConsensusState.Leader);
  writeln("  PASS: Five-node cluster majority");
  passed += 1;

  writeln("\n  Consensus: ", passed, "/", total, " tests passed");
  assert(passed == total);
}
