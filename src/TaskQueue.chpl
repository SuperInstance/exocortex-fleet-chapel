// TaskQueue.chpl — Distributed task scheduling for the exocortex fleet
// Part of the ExocortexFleet distributed coordination system
//
// The TaskQueue is a priority-aware FIFO that tracks which tasks are
// pending, assigned, and completed. In a full distributed system each
// locale would run its own queue shard; here we model the centralized
// view for clarity and testability.
//
// Design note: TaskQueue is a *class* (reference type) because it
// owns mutable state that multiple parts of the system share — the
// consensus module, the heartbeat monitor, and the topology manager
// all reference the same queue.

module TaskQueue {

  /// A unit of work in the fleet.
  ///
  /// Records are value types — when a task is dequeued and assigned,
  /// the caller gets an independent copy. This prevents accidental
  /// mutation after assignment.
  record Task {
    var id: string;
    var task_type: string;
    var priority: int;          // higher = more urgent
    var payload: string;        // opaque work description
    var assigned_to: string;    // empty string means unassigned
  }

  /// A priority-aware task queue with assignment tracking.
  ///
  /// Internally uses a sorted array. For a production fleet with
  /// millions of tasks, you'd swap this for a heap or a lock-free
  /// skip list. The interface stays the same.
  class TaskQueue {
    var tasks: [0..#1024] Task; // fixed-size for simplicity; growable in production
    var task_count: int = 0;

    // ── Enqueue ──────────────────────────────────────────────────

    /// Add a task to the queue, maintaining priority order.
    ///
    /// Higher-priority tasks sort first. Within the same priority,
    /// FIFO order is preserved (stable insertion).
    proc enqueue(task: Task) {
      if task_count >= tasks.size {
        // In production: grow the array or spill to disk
        halt("TaskQueue full — cannot enqueue " + task.id);
      }

      // Find insertion point: first position where existing priority < new priority
      var insert_at = task_count;
      for i in 0..#task_count {
        if tasks[i].priority < task.priority {
          insert_at = i;
          break;
        }
      }

      // Shift elements right to make room
      for i in insert_at..task_count-1 by -1 {
        tasks[i+1] = tasks[i];
      }
      tasks[insert_at] = task;
      task_count += 1;
    }

    // ── Dequeue ──────────────────────────────────────────────────

    /// Remove and return the highest-priority *unassigned* task.
    /// Returns a dummy task with id="" if the queue is empty or
    /// all tasks are assigned.
    proc dequeue(): Task {
      for i in 0..#task_count {
        if tasks[i].assigned_to == "" {
          const t = tasks[i];
          // Remove by shifting left
          for j in i..task_count-2 {
            tasks[j] = tasks[j+1];
          }
          task_count -= 1;
          tasks[task_count] = new Task(); // clear last slot
          return t;
        }
      }
      return new Task(); // empty sentinel
    }

    // ── Assign / Complete ─────────────────────────────────────────

    /// Mark a task as assigned to a specific node.
    proc assign(task_id: string, node_id: string) {
      for i in 0..#task_count {
        if tasks[i].id == task_id {
          tasks[i].assigned_to = node_id;
          return;
        }
      }
    }

    /// Remove a completed task from the queue entirely.
    proc complete(task_id: string) {
      for i in 0..#task_count {
        if tasks[i].id == task_id {
          for j in i..task_count-2 {
            tasks[j] = tasks[j+1];
          }
          task_count -= 1;
          tasks[task_count] = new Task();
          return;
        }
      }
    }

    // ── Query ─────────────────────────────────────────────────────

    /// Count of tasks still pending (unassigned).
    proc pending_count(): int {
      var count = 0;
      for i in 0..#task_count {
        if tasks[i].assigned_to == "" then count += 1;
      }
      return count;
    }

    /// Total tasks in the queue (pending + assigned).
    proc total_count(): int {
      return task_count;
    }
  }

} // module TaskQueue
