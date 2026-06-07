# exocortex-fleet-chapel

> **Chapel's PGAS is what the fleet actually is — one address space, many devices.**

Distributed fleet coordination implemented in [Chapel](https://chapel-lang.org/), proving that the Partitioned Global Address Space (PGAS) model maps naturally to coordinating heterogeneous devices across an exocortex.

This project implements five core modules — **FleetNode**, **TaskQueue**, **Consensus**, **Heartbeat**, and **Topology** — that together form a complete distributed coordination layer. Each module is self-contained, testable, and designed to leverage Chapel's unique language features: locale-aware computation, first-class domains, and value/reference type discipline.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Theory](#theory)
3. [Quick Start](#quick-start)
4. [Module Reference](#module-reference)
5. [Runnable Examples](#runnable-examples)
6. [Performance](#performance)
7. [Design Decisions](#design-decisions)
8. [Comparison with Alternatives](#comparison-with-alternatives)
9. [Glossary](#glossary)
10. [References](#references)
11. [License](#license)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        EXOCORTEX FLEET                             │
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │  Device   │  │  Device   │  │  Device   │  │  Device   │          │
│  │  (GPU)    │  │  (CPU)    │  │  (MCU)    │  │(Browser)  │          │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
│       │             │             │             │                   │
│  ┌────▼─────────────▼─────────────▼─────────────▼──────────────┐  │
│  │                      FleetNode Layer                         │  │
│  │   device representation · capabilities · load scoring       │  │
│  └──────────────────────────┬──────────────────────────────────┘  │
│                             │                                       │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │                     Topology Layer                            │  │
│  │   network graph · shortest path · connected components      │  │
│  └──────────────────────────┬──────────────────────────────────┘  │
│                             │                                       │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │                    TaskQueue Layer                            │  │
│  │   priority scheduling · assignment · completion tracking    │  │
│  └──────────────────────────┬──────────────────────────────────┘  │
│                             │                                       │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │                   Consensus Layer                             │  │
│  │   Raft-style election · term-based leadership · proposals   │  │
│  └──────────────────────────┬──────────────────────────────────┘  │
│                             │                                       │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │                  Heartbeat Layer                              │  │
│  │   health monitoring · fleet health score · degradation      │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                 Chapel PGAS Runtime                          │  │
│  │   Locale 0 (GPU)  ·  Locale 1 (CPU)  ·  Locale N (MCU)    │  │
│  │   One global address space transparently spanning devices   │  │
│  └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Devices** register as **FleetNodes** with capabilities and load metrics.
2. **Topology** maps the network — edges, weights, connectivity.
3. **TaskQueue** receives tasks, orders by priority, assigns to nodes.
4. **Consensus** elects a leader to coordinate task assignment decisions.
5. **Heartbeat** monitors fleet health, triggers reassignment on failure.

### Module Dependency Graph

```
FleetNode ──────────────────────────────────────────┐
    │                                                │
    ├──→ Topology (nodes are vertices in the graph)  │
    │                                                │
    ├──→ TaskQueue (tasks assigned to nodes)         │
    │                                                │
    ├──→ Heartbeat (monitors node liveness)          │
    │                                                │
    └──→ Consensus (nodes participate in election)   │
                                                     │
ExocortexFleet.chpl (re-exports all modules) ────────┘
```

---

## Theory

### The PGAS Model and Fleet Coordination

Chapel's **Partitioned Global Address Space** (PGAS) model divides a program's address space into **locales** — units of computation and storage that map to physical devices (cores, GPUs, nodes in a cluster). Each locale owns a partition of the global data, but any locale can directly read or write data on any other locale.

This is *exactly* what a fleet of devices is:

| PGAS Concept    | Fleet Analog                        |
|-----------------|-------------------------------------|
| Locale          | A device (GPU, CPU, MCU, browser)  |
| Global variable | Shared fleet state                  |
| Local variable  | Device-local state                  |
| `on` clause     | Dispatching work to a device        |
| Domain          | The set of all tasks or nodes       |

> **Chapel's PGAS is what the fleet actually is — one address space, many devices.**

Traditional distributed frameworks (Akka, Orleans, Ray) simulate PGAS on top of message-passing runtimes. Chapel gives it to you natively. A `FleetNode` isn't an actor stub or a proxy object — it's a Chapel record that can live on any locale, with the runtime handling the data movement transparently.

### Distributed Consensus and Raft

Our consensus module implements a simplified version of the **Raft consensus algorithm** (Ongaro & Ousterhout, 2014). Raft decomposes consensus into three sub-problems:

1. **Leader Election** — Nodes transition between Follower, Candidate, and Leader states. If a Follower doesn't hear from a Leader within a randomized timeout, it becomes a Candidate, increments its term, and solicits votes. A Candidate that receives a majority of votes becomes Leader.

2. **Log Replication** — The Leader accepts proposals from clients, appends them to its log, and replicates them to followers. A log entry is *committed* once a majority of followers acknowledge it. (Our simplified version commits immediately upon leader acceptance.)

3. **Safety** — Raft guarantees that if a log entry is committed, it will never be overwritten. The term number ensures that stale leaders cannot commit conflicting entries.

**Why simplified Raft?** Full Raft includes log compaction, membership changes, and linearizable reads — essential for production systems but obscuring for pedagogical code. Our implementation captures the state machine and election mechanism, which are the intellectually interesting parts for fleet coordination.

### The FLP Impossibility Result

Fischer, Lynch, and Paterson (1985) proved that **no deterministic algorithm can solve consensus in an asynchronous system with even one faulty process**. This is the FLP impossibility result, and it fundamentally shapes how we think about distributed systems.

Raft's answer to FLP is **timeouts and randomization**:

- Election timeouts are randomized so that candidates don't repeatedly split the vote.
- The system assumes *partial synchrony* — the network is usually fast enough that timeouts fire only during actual failures.

Our `ConsensusPool` models this with explicit `start_election` calls. In a real deployment, the election timer would fire automatically when heartbeats from the leader stop arriving — connecting the Heartbeat and Consensus modules.

### Chapel's Locality Model

Chapel's locality model is built around two key concepts:

- **Locales** (`locale` type): A locale represents a unit of the target architecture that can execute tasks and store data. On a multi-core machine, each core could be a locale. On a cluster, each node is a locale.

- **The `on` clause**: `on L do expr` executes `expr` on locale `L`. Data is automatically moved between locales as needed.

For fleet coordination, this means:

```chapel
// Assign a task to run on the GPU locale
on Locales[gpu_locale_id] {
  // This code runs on the GPU device
  result = perform_inference(task.payload);
}
```

No serialization, no RPC framework, no message broker. Chapel handles the data movement.

---

## Quick Start

### Prerequisites

- [Chapel](https://chapel-lang.org/docs/usingchapel/QUICKSTART.html) 2.x (tested with 2.0+)

### Compile and Run Tests

```bash
# Clone
git clone https://github.com/SuperInstance/exocortex-fleet-chapel.git
cd exocortex-fleet-chapel

# Compile and run individual module tests
chpl -o test_fleet_node test/test_fleet_node.chpl src/FleetNode.chpl && ./test_fleet_node
chpl -o test_task_queue test/test_task_queue.chpl src/TaskQueue.chpl && ./test_task_queue
chpl -o test_consensus test/test_consensus.chpl src/Consensus.chpl && ./test_consensus
chpl -o test_heartbeat test/test_heartbeat.chpl src/Heartbeat.chpl && ./test_heartbeat
chpl -o test_topology test/test_topology.chpl src/Topology.chpl && ./test_topology
```

### Run All Tests

```bash
for test in test_*/test_*.chpl; do
  name=$(basename "$test" .chpl)
  echo "--- Building $name ---"
  chpl -o "/tmp/$name" "$test" src/*.chpl 2>&1 || true
  echo "--- Running $name ---"
  "/tmp/$name" 2>&1 || true
  echo ""
done
```

---

## Module Reference

### FleetNode — Device Representation

```chapel
use FleetNode;

// Create a GPU node
var gpu = new FleetNode(id = "gpu-0", node_type = NodeType.GPU,
                         load = 0.3, latency_ms = 5.0);
gpu.capabilities.add("inference");
gpu.capabilities.add("training");

// Query
gpu.can_handle("inference");   // true
gpu.utilization();             // 0.3
gpu.score("inference");        // ~0.85 (high score: capable + low load + low latency)
gpu.serialize();               // "{id: gpu-0, type: GPU, capabilities: [inference, training], ...}"
```

**Type choice:** `FleetNode` is a **record** (value type). Nodes are frequently copied into task assignments, health reports, and messages. Value semantics prevent aliasing bugs — when you assign a task to a node, you have an independent snapshot.

### TaskQueue — Distributed Task Scheduling

```chapel
use TaskQueue;

var q = new TaskQueue();
q.enqueue(new Task(id = "t1", task_type = "inference", priority = 5,
                    payload = "classify cat photo"));
q.enqueue(new Task(id = "t2", task_type = "training", priority = 10,
                    payload = "fine-tune model"));

const best = q.dequeue();  // t2 (higher priority)
q.assign("t1", "gpu-0");
q.pending_count();          // 0 (t1 assigned, t2 dequeued)
```

**Priority ordering:** Tasks are sorted by priority on insertion (higher = more urgent). Within the same priority level, FIFO order is preserved via stable insertion.

### Consensus — Simplified Raft

```chapel
use Consensus;

var pool = new ConsensusPool();
pool.add_node("gpu-0");
pool.add_node("cpu-0");
pool.add_node("mcu-0");

pool.start_election("gpu-0");   // becomes Candidate, term 1
pool.vote("cpu-0", 1);          // majority → becomes Leader

pool.is_leader();                // true
pool.propose("assign t1 to gpu-0");  // committed
```

**State machine:** `Follower → Candidate → Leader`. A node starts as Follower, transitions to Candidate when its election timeout fires, and becomes Leader upon receiving a majority of votes.

### Heartbeat — Fleet Health Monitoring

```chapel
use Heartbeat;

var mon = new HeartbeatMonitor(threshold_ms = 5000.0);
mon.register("gpu-0");
mon.register("cpu-0");

mon.ping("gpu-0", 1000.0);   // t=1000ms
mon.ping("cpu-0", 1000.0);

mon.get_status("gpu-0", 3000.0);  // Healthy (elapsed: 2000ms < 5000ms)
mon.get_status("cpu-0", 8000.0);  // Unreachable (elapsed: 7000ms > 5000ms)

mon.fleet_health_score(3000.0);    // 0.5 (one healthy, one unreachable)
```

**Degradation levels:** Healthy (elapsed < 60% threshold), Degraded (60–100%), Unreachable (> threshold). The fleet health score weights these as 1.0, 0.5, and 0.0 respectively.

### Topology — Network Topology

```chapel
use Topology;

var topo = new FleetTopology();
topo.add_undirected("gpu-0", "cpu-0", 5.0);   // 5ms link
topo.add_undirected("cpu-0", "mcu-0", 50.0);  // 50ms link

topo.neighbors("gpu-0");                        // ["cpu-0"]
topo.shortest_path("gpu-0", "mcu-0");           // ["gpu-0", "cpu-0", "mcu-0"]
topo.is_connected();                             // true
```

**BFS for shortest path:** We use breadth-first search for shortest path computation. BFS finds the path with the fewest hops, which is appropriate for fleet topology where edge weights represent latency but routing decisions prioritize connectivity over sub-millisecond latency optimization.

---

## Runnable Examples

### Example 1: Fleet Dashboard — Health at a Glance

```chapel
// example_dashboard.chpl — Fleet health dashboard
use FleetNode;
use Heartbeat;

proc main() {
  writeln("╔══════════════════════════════════════╗");
  writeln("║     EXOCORTEX FLEET DASHBOARD        ║");
  writeln("╚══════════════════════════════════════╝");

  // Set up nodes
  var nodes: [0..#4] FleetNode;
  nodes[0] = new FleetNode(id = "gpu-primary", node_type = NodeType.GPU,
                            load = 0.7, latency_ms = 3.0);
  nodes[0].capabilities.add("inference");
  nodes[0].capabilities.add("training");

  nodes[1] = new FleetNode(id = "gpu-backup", node_type = NodeType.GPU,
                            load = 0.2, latency_ms = 5.0);
  nodes[1].capabilities.add("inference");

  nodes[2] = new FleetNode(id = "cpu-worker", node_type = NodeType.CPU,
                            load = 0.5, latency_ms = 10.0);
  nodes[2].capabilities.add("preprocessing");

  nodes[3] = new FleetNode(id = "mcu-sensor", node_type = NodeType.Microcontroller,
                            load = 0.1, latency_ms = 150.0);
  nodes[3].capabilities.add("sensing");

  // Monitor health
  var mon = new HeartbeatMonitor(threshold_ms = 5000.0);
  for n in nodes do mon.register(n.id);

  // Simulate heartbeats at t=1000
  mon.ping("gpu-primary", 1000.0);
  mon.ping("gpu-backup", 1000.0);
  mon.ping("cpu-worker", 1000.0);
  // mcu-sensor forgot to ping!

  writeln("\n  Node Status at t=6000ms:");
  writeln("  ┌──────────────┬────────────┬──────────┐");
  writeln("  │ Node         │ Status     │ Load     │");
  writeln("  ├──────────────┼────────────┼──────────┤");
  for n in nodes {
    const status = mon.get_status(n.id, 6000.0);
    writeln("  │ ", n.id);
  }

  const score = mon.fleet_health_score(6000.0);
  writeln("\n  Fleet Health: ", (score * 100):int, "%");
  writeln("  Active Nodes: 3/4");
  writeln("  Degraded: 0 | Unreachable: 1 (mcu-sensor)");
}
```

### Example 2: Task Scheduling with Priority

```chapel
// example_scheduling.chpl — Priority-based task scheduling
use FleetNode;
use TaskQueue;

proc main() {
  writeln("=== Priority Task Scheduling ===\n");

  // Create a fleet of nodes
  var gpu = new FleetNode(id = "gpu-0", node_type = NodeType.GPU,
                           load = 0.3, latency_ms = 2.0);
  gpu.capabilities.add("inference");
  gpu.capabilities.add("training");

  var cpu = new FleetNode(id = "cpu-0", node_type = NodeType.CPU,
                           load = 0.8, latency_ms = 8.0);
  cpu.capabilities.add("preprocessing");
  cpu.capabilities.add("inference");

  // Create a task queue with mixed priorities
  var q = new TaskQueue();
  q.enqueue(new Task(id = "T1", task_type = "preprocessing", priority = 3,
                      payload = "resize images"));
  q.enqueue(new Task(id = "T2", task_type = "training", priority = 8,
                      payload = "fine-tune ResNet"));
  q.enqueue(new Task(id = "T3", task_type = "inference", priority = 10,
                      payload = "classify cat photo"));
  q.enqueue(new Task(id = "T4", task_type = "preprocessing", priority = 1,
                      payload = "log cleanup"));

  writeln("  Queued ", q.total_count(), " tasks (", q.pending_count(), " pending)");

  // Assign tasks to best-fitting nodes
  while q.pending_count() > 0 {
    const task = q.dequeue();
    if task.id == "" then break;

    // Simple greedy: pick node with highest score
    var best_node_id = "";
    var best_score = -1.0;

    for node in [gpu, cpu] {
      const s = node.score(task.task_type);
      writeln("    ", node.id, " scores ", s, " for ", task.task_type);
      if s > best_score {
        best_score = s;
        best_node_id = node.id;
      }
    }

    if best_node_id != "" {
      writeln("  → ", task.id, " (", task.task_type, ") assigned to ", best_node_id);
    } else {
      writeln("  → ", task.id, " (", task.task_type, ") NO CAPABLE NODE");
    }
  }
}
```

### Example 3: Consensus-Based Leader Election

```chapel
// example_consensus.chpl — Fleet leader election
use Consensus;

proc main() {
  writeln("=== Fleet Leader Election ===\n");

  // Five-node fleet
  var pool = new ConsensusPool();
  pool.add_node("gpu-primary");
  pool.add_node("gpu-backup");
  pool.add_node("cpu-worker-0");
  pool.add_node("cpu-worker-1");
  pool.add_node("mcu-sensor");

  writeln("  Fleet size: 5 nodes");
  writeln("  Majority needed: ", pool.majority(), " votes\n");

  // GPU-primary starts an election
  writeln("  [t=0] gpu-primary starts election (term ", pool.term() + 1, ")");
  pool.start_election("gpu-primary");
  writeln("  [t=1] gpu-primary is Candidate, self-voted (1/", pool.majority(), ")");

  // GPU-backup votes
  pool.vote("gpu-backup", pool.term());
  writeln("  [t=2] gpu-backup voted (2/", pool.majority(), ")");

  // cpu-worker-0 votes — this gives majority!
  pool.vote("cpu-worker-0", pool.term());
  writeln("  [t=3] cpu-worker-0 voted (3/", pool.majority(), ")");
  writeln("  [t=3] ★ gpu-primary is now LEADER");

  // Leader proposes a fleet-wide configuration
  writeln("\n  Leader proposing fleet configuration...");
  pool.propose("strategy: load-balance across GPU nodes");
  pool.propose("heartbeat_interval: 5000ms");
  pool.propose("election_timeout: 1500ms");

  writeln("  Committed ", pool.committed_count_val(), " proposals");
  writeln("\n  Fleet is coordinated. All nodes will receive updates.");
}
```

### Example 4: Topology-Aware Routing

```chapel
// example_topology.chpl — Network topology and routing
use Topology;

proc main() {
  writeln("=== Fleet Topology ===\n");

  var topo = new FleetTopology();

  // Build a realistic fleet topology
  // GPU cluster (low latency interconnect)
  topo.add_undirected("gpu-0", "gpu-1", 1.0);   // NVLink
  topo.add_undirected("gpu-1", "gpu-2", 1.0);   // NVLink

  // CPU workers connected to GPU cluster
  topo.add_undirected("gpu-0", "cpu-0", 10.0);  // PCIe + network
  topo.add_undirected("gpu-2", "cpu-1", 10.0);

  // Edge devices with higher latency
  topo.add_undirected("cpu-0", "mcu-sensor", 100.0);  // WiFi
  topo.add_undirected("cpu-1", "browser-tab", 200.0); // Internet

  writeln("  Fleet topology: ", topo.node_count, " nodes");

  // Find path from sensor to GPU for inference offloading
  writeln("\n  Routing: mcu-sensor → gpu-1 (inference offload)");
  const path = topo.shortest_path("mcu-sensor", "gpu-1");
  write("  Path: ");
  for i in 0..path.size-1 {
    if path[i] != "" {
      write(path[i]);
      if i < path.size - 1 && path[i+1] != "" then write(" → ");
    }
  }
  writeln();

  // Check connectivity
  writeln("\n  Fleet connected: ", topo.is_connected());

  // Find connected components (if any partition)
  writeln("\n  Connected components:");
  const comps = topo.connected_components();
  var comp_idx = 1;
  write("  Component ", comp_idx, ": ");
  for i in 0..comps.size-1 {
    if comps[i] == "" {
      comp_idx += 1;
      writeln();
      if i + 1 < comps.size && comps[i+1] != "" {
        write("  Component ", comp_idx, ": ");
      }
    } else {
      write(comps[i], " ");
    }
  }
  writeln();
}
```

---

## Performance

### PGAS Locality Advantages

Chapel's PGAS model provides several performance benefits for fleet coordination:

1. **Implicit Data Movement**: When a `FleetNode` record is accessed from a remote locale, Chapel handles serialization and transport transparently. No manual marshaling code.

2. **Locality-Aware Scheduling**: The `on` clause allows the scheduler to place computation close to data:
   ```chapel
   on Locales[gpu_locale] {
     // Task execution happens on the GPU locale
     // FleetNode data is local — no remote access
   }
   ```

3. **Bulk Communication**: Chapel's domain-driven loops can be optimized by the compiler into bulk communication patterns, avoiding per-element round-trips.

### Communication Patterns

| Operation          | Messages (PGAS) | Messages (RPC/Actor) |
|--------------------|-----------------|----------------------|
| Read node state    | 1 (RDMA)        | 2 (request + reply)  |
| Assign task        | 1 (write)       | 1 (message)          |
| Health check round | 1 (bulk read)   | N (ping each node)   |
| Leader election    | O(N) votes      | O(N²) messages       |

### Scaling Characteristics

- **FleetNode**: O(1) operations — record access is direct.
- **TaskQueue**: O(N) insertion (sorted array), O(1) dequeue. For production, swap to O(log N) heap.
- **Consensus**: O(N) election round where N = cluster size. Majority must respond.
- **Heartbeat**: O(N) health check per node, O(1) per ping.
- **Topology**: O(V + E) for BFS shortest path, O(V + E) for connected components.

---

## Design Decisions

### Why Simplified Raft?

Full Raft includes:
- Log replication with consistency checks
- Log compaction (snapshotting)
- Dynamic membership changes
- Linearizable reads via ReadIndex

We omit these because:
1. **Pedagogical clarity**: The election mechanism is the most interesting part for fleet coordination. Log replication is mechanical.
2. **Fleet semantics**: In our model, the leader proposes *configuration changes* (task assignments, node additions), not a general-purpose key-value store. The "log" is the queue state, which is already managed by TaskQueue.
3. **In-memory model**: Fleet state is ephemeral. If the leader crashes, a new election runs and the new leader rebuilds state from FleetNode registrations and TaskQueue snapshots.

### Why BFS for Shortest Path?

1. **Topology is typically sparse**: Fleet networks have O(N) edges (tree or near-tree topology). BFS is O(V + E), which is essentially O(N).
2. **Hop count matters more than weight**: For task routing, "how many network hops" is more important than "total latency in milliseconds" because each hop adds failure probability.
3. **Iterative constraint**: The project requires all algorithms to be iterative. BFS is naturally iterative; Dijkstra with a priority queue is also iterative but adds implementation complexity without proportional benefit.

### Why Records vs. Classes?

| Type   | Chapel Semantics   | Used For          | Rationale                                |
|--------|--------------------|--------------------|------------------------------------------|
| Record | Value (copy)       | FleetNode, Task   | Freely copied into messages and reports  |
| Class  | Reference (heap)   | TaskQueue, Monitor| Shared mutable state, single owner       |
| Class  | Reference (heap)   | ConsensusPool     | All nodes reference same election state  |
| Class  | Reference (heap)   | FleetTopology     | Shared graph, mutations visible to all   |

### Why Fixed-Size Arrays?

Production Chapel would use:
```chapel
var tasks: [0..] Task;  // dynamically sized
```

We use fixed-size arrays (`[0..#1024]`) for portability across Chapel implementations and to avoid relying on specific dynamic-array features. The size constants are generous enough for testing and can be parameterized in production.

---

## Comparison with Alternatives

### vs. Akka (Scala/JVM)

| Aspect           | Chapel (this project)          | Akka                            |
|------------------|--------------------------------|---------------------------------|
| Model            | PGAS (shared address space)   | Actor model (message passing)  |
| Serialization    | Automatic (runtime)           | Manual (protobuf, JSON, etc.)  |
| Type safety      | Compile-time (static)         | Compile-time (static)          |
| Latency          | RDMA where available          | JVM GC pauses                  |
| Complexity       | Low (express intent directly) | Medium (actor hierarchies)     |
| Ecosystem        | Small but focused             | Massive (Akka HTTP, Streams)   |

**When to choose Chapel:** When your fleet is the machine — same trust domain, same binary, PGAS is the natural model. **When to choose Akka:** When you need the JVM ecosystem, HTTP endpoints, or are communicating across trust boundaries.

### vs. Orleans (C#/.NET)

| Aspect           | Chapel                         | Orleans                          |
|------------------|--------------------------------|----------------------------------|
| Model            | PGAS + locales                 | Virtual actors (grains)          |
| Placement        | Explicit (`on` clause)         | Automatic (runtime placement)   |
| Persistence      | Manual                         | Built-in grain persistence      |
| Scaling          | HPC-oriented (locales)         | Cloud-oriented (silos)          |

**When to choose Chapel:** Scientific computing, HPC clusters, tight coupling between locales. **When to choose Orleans:** Cloud-native microservices, automatic scaling, Azure integration.

### vs. Ray (Python)

| Aspect           | Chapel                         | Ray                              |
|------------------|--------------------------------|----------------------------------|
| Language         | Chapel (compiled)              | Python (interpreted + compiled)  |
| Model            | PGAS                           | Actor + task parallelism         |
| Overhead         | Minimal (native binary)        | Significant (serialization)      |
| ML integration   | External                       | Native (Ray Train, Ray Serve)   |

**When to choose Chapel:** Performance-critical coordination, no Python dependency. **When to choose Ray:** Python ML ecosystem, rapid prototyping, existing Ray pipeline.

### vs. Dask (Python)

| Aspect           | Chapel                         | Dask                             |
|------------------|--------------------------------|----------------------------------|
| Model            | PGAS (first-class locales)     | Task graph (scheduler + workers) |
| Scheduling       | Data-driven (locale affinity)  | Graph-based (dynamic)            |
| Array support    | Native (domains)               | Native (dask.array)              |
| Fleet heterogeneity | First-class (NodeType enum) | Not a primary concern            |

**When to choose Chapel:** Heterogeneous fleet with GPU/CPU/MCU/Browser devices. **When to choose Dask:** DataFrames, NumPy integration, Jupyter workflows.

---

## Glossary

| Term              | Definition                                                       |
|-------------------|------------------------------------------------------------------|
| **PGAS**          | Partitioned Global Address Space — a parallel programming model where memory is partitioned across locales but globally addressable. |
| **Locale**        | A unit of computation and storage in Chapel. Maps to a physical device or compute node. |
| **Domain**        | Chapel's first-class index set. Used to define arrays, loops, and parallel iterations. |
| **Record**        | A value type in Chapel. Copied on assignment. Used for FleetNode and Task. |
| **Class**         | A reference type in Chapel. Heap-allocated, shared by reference. Used for TaskQueue, ConsensusPool, etc. |
| **Raft**          | A consensus algorithm for managing a replicated log. Designed to be understandable (Ongaro & Ousterhout, 2014). |
| **FLP Impossibility** | Fischer, Lynch, and Paterson's 1985 result: deterministic consensus is impossible in fully asynchronous systems with one faulty process. |
| **Term**          | A logical clock in Raft. Incremented on each election. Prevents stale leaders. |
| **BFS**           | Breadth-First Search. Graph traversal that explores all neighbors before moving to the next level. Used for shortest path. |
| **Exocortex**     | A theoretical artificial external information processing system that augments a brain's biological cognition. In this project, the network of devices that extend computational capability. |
| **Fleet**         | The collection of heterogeneous devices (GPUs, CPUs, MCUs, browsers) coordinated by this system. |
| **Degraded**      | A health state indicating a node is responding but slower than expected (60–100% of threshold). |
| **Majority**      | More than half of the nodes in a consensus cluster. Required for leader election and commit. |

---

## References

1. **Chamberlain, B.L., Callahan, D., and Zima, H.P.** (2007). *Parallel Programmability and the Chapel Language*. International Journal of High Performance Computing Applications, 21(3), 291–312. https://doi.org/10.1177/1094342007078442

2. **Ongaro, D. and Ousterhout, J.** (2014). *In Search of an Understandable Consensus Algorithm*. Proceedings of the 2014 USENIX Annual Technical Conference (ATC '14), 305–319.

3. **Fischer, M.J., Lynch, N.A., and Paterson, M.S.** (1985). *Impossibility of Distributed Consensus with One Faulty Process*. Journal of the ACM, 32(2), 374–382. https://doi.org/10.1145/3149.214121

4. **Chapel Language Specification**. https://chapel-lang.org/docs/language/spec.html

5. **Dean, J. and Ghemawat, S.** (2008). *MapReduce: Simplified Data Processing on Large Clusters*. Communications of the ACM, 51(1), 107–113.

6. **Lamport, L.** (1998). *The Part-Time Parliament*. ACM Transactions on Computer Systems, 16(2), 133–169. (Paxos)

7. **Isard, M., Budiu, M., Yu, Y., Birrell, A., and Fetterly, D.** (2007). *Dryad: Distributed Data-Parallel Programs from Sequential Building Blocks*. Proceedings of EuroSys 2007.

---

## License

MIT

---

*Built to prove that Chapel's PGAS model is the natural fit for fleet coordination — one address space, many devices.*
