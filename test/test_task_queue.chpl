// test_task_queue.chpl — Tests for the TaskQueue module
use TaskQueue;

proc main() {
  writeln("=== TaskQueue Tests ===");
  var passed = 0;
  var total = 0;

  // Test 1: Create queue and enqueue
  total += 1;
  var q = new TaskQueue();
  q.enqueue(new Task(id = "t1", task_type = "inference", priority = 5,
                      payload = "classify image", assigned_to = ""));
  assert(q.total_count() == 1);
  assert(q.pending_count() == 1);
  writeln("  PASS: Enqueue single task");
  passed += 1;

  // Test 2: Dequeue returns highest priority
  total += 1;
  q.enqueue(new Task(id = "t2", task_type = "training", priority = 10,
                      payload = "fine-tune model", assigned_to = ""));
  q.enqueue(new Task(id = "t3", task_type = "sensing", priority = 3,
                      payload = "read sensor", assigned_to = ""));
  const t = q.dequeue();
  assert(t.id == "t2"); // priority 10
  assert(q.pending_count() == 2); // t1 and t3 remain
  writeln("  PASS: Dequeue returns highest priority");
  passed += 1;

  // Test 3: Assign a task
  total += 1;
  q.assign("t1", "gpu-0");
  assert(q.pending_count() == 1); // only t3 is pending now
  writeln("  PASS: Assign task");
  passed += 1;

  // Test 4: Dequeue skips assigned tasks
  total += 1;
  const t3 = q.dequeue();
  assert(t3.id == "t3"); // t1 is assigned, so t3 is next
  writeln("  PASS: Dequeue skips assigned tasks");
  passed += 1;

  // Test 5: Complete a task
  total += 1;
  q.enqueue(new Task(id = "t4", task_type = "inference", priority = 1,
                      payload = "test", assigned_to = ""));
  q.complete("t1");
  // t1 was assigned to gpu-0, now it's gone
  assert(q.total_count() == 1); // only t4 left
  writeln("  PASS: Complete removes task");
  passed += 1;

  // Test 6: Empty queue returns empty task
  total += 1;
  var q2 = new TaskQueue();
  const empty = q2.dequeue();
  assert(empty.id == "");
  writeln("  PASS: Empty queue returns sentinel");
  passed += 1;

  // Test 7: Priority ordering is stable
  total += 1;
  var q3 = new TaskQueue();
  q3.enqueue(new Task(id = "a", task_type = "x", priority = 1, payload = "", assigned_to = ""));
  q3.enqueue(new Task(id = "b", task_type = "x", priority = 1, payload = "", assigned_to = ""));
  q3.enqueue(new Task(id = "c", task_type = "x", priority = 5, payload = "", assigned_to = ""));
  const first = q3.dequeue();
  assert(first.id == "c"); // highest priority
  const second = q3.dequeue();
  assert(second.id == "a"); // FIFO within same priority
  writeln("  PASS: Stable priority ordering");
  passed += 1;

  // Test 8: pending_count after mixed operations
  total += 1;
  var q4 = new TaskQueue();
  q4.enqueue(new Task(id = "p1", task_type = "x", priority = 1, payload = "", assigned_to = ""));
  q4.enqueue(new Task(id = "p2", task_type = "x", priority = 1, payload = "", assigned_to = ""));
  q4.assign("p1", "node-a");
  assert(q4.pending_count() == 1);
  q4.complete("p1");
  assert(q4.total_count() == 1);
  assert(q4.pending_count() == 1);
  writeln("  PASS: pending_count after mixed ops");
  passed += 1;

  // Test 9: Multiple dequeues drain the queue
  total += 1;
  var q5 = new TaskQueue();
  for i in 1..5 {
    q5.enqueue(new Task(id = "m" + i:string, task_type = "x", priority = i,
                         payload = "", assigned_to = ""));
  }
  for i in 1..5 {
    const t = q5.dequeue();
    assert(t.id != "");
  }
  assert(q5.total_count() == 0);
  assert(q5.pending_count() == 0);
  writeln("  PASS: Drain queue with dequeues");
  passed += 1;

  writeln("\n  TaskQueue: ", passed, "/", total, " tests passed");
  assert(passed == total);
}
