// ExocortexFleet.chpl — Main module: distributed fleet coordination
// Part of the ExocortexFleet distributed coordination system
//
// This is the top-level module that re-exports all submodules.
// Compile this file to build the entire fleet coordination library.
//
// ┌─────────────────────────────────────────────────────────────────┐
// │                    EXOCORTEX FLEET ARCHITECTURE                │
// │                                                                 │
// │  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   │
// │  │  Device   │   │  Device   │   │  Device   │   │  Device   │   │
// │  │  (GPU)    │   │  (CPU)    │   │  (MCU)    │   │(Browser)  │   │
// │  └────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘   │
// │       │              │              │              │            │
// │  ┌────▼─────────────▼──────────────▼──────────────▼─────┐     │
// │  │                   FleetNode Layer                     │     │
// │  │    (device representation, capabilities, scoring)    │     │
// │  └─────────────────────┬───────────────────────────────┘     │
// │                        │                                        │
// │  ┌─────────────────────▼───────────────────────────────┐     │
// │  │                 Topology Layer                        │     │
// │  │    (network graph, shortest path, connectivity)      │     │
// │  └─────────────────────┬───────────────────────────────┘     │
// │                        │                                        │
// │  ┌─────────────────────▼───────────────────────────────┐     │
// │  │                TaskQueue Layer                        │     │
// │  │    (priority scheduling, assignment, completion)     │     │
// │  └─────────────────────┬───────────────────────────────┘     │
// │                        │                                        │
// │  ┌─────────────────────▼───────────────────────────────┐     │
// │  │               Consensus Layer                        │     │
// │  │    (Raft-style leader election, proposals)           │     │
// │  └─────────────────────┬───────────────────────────────┘     │
// │                        │                                        │
// │  ┌─────────────────────▼───────────────────────────────┐     │
// │  │              Heartbeat Layer                         │     │
// │  │    (health monitoring, fleet health score)           │     │
// │  └─────────────────────────────────────────────────────┘     │
// │                                                                 │
// │  Chapel's PGAS is what the fleet actually is:                  │
// │  one address space, many devices.                              │
// └─────────────────────────────────────────────────────────────────┘

module ExocortexFleet {
  public use FleetNode;
  public use TaskQueue;
  public use Consensus;
  public use Heartbeat;
  public use Topology;
}
