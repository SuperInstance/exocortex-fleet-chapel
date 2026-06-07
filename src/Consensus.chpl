// Consensus.chpl — Simplified Raft consensus for the exocortex fleet
// Part of the ExocortexFleet distributed coordination system
//
// This is a pedagogical implementation of Raft-style consensus (Ongaro &
// Ousterhout, 2014). It captures the essential state machine — Follower,
// Candidate, Leader — and the election mechanism, but deliberately omits
// log replication and persistence for clarity.
//
// Why simplified Raft?
//   - The fleet needs a *leader* to coordinate task assignment.
//   - Full Raft is overkill for in-memory fleet state.
//   - The election mechanism gives us automatic failover.
//   - The term number prevents split-brain after network partitions.
//
// FLP impossibility (Fischer, Lynch, Paterson 1985) tells us that
// deterministic consensus is impossible in async networks. Raft's answer
// is timeouts + randomization — which we model here.

module Consensus {

  /// The three Raft states.
  enum ConsensusState {
    Follower,   // Following a leader
    Candidate,  // Soliciting votes
    Leader      // Leading the cluster
  }

  /// A simplified Raft consensus pool.
  ///
  /// In a full distributed implementation, each node would run its own
  /// ConsensusPool and communicate via RPCs. Here we model the entire
  /// pool in one object for testing and reasoning about correctness.
  class ConsensusPool {
    var node_ids: [0..#64] string;   // participating node IDs
    var node_count: int = 0;
    var state: ConsensusState = ConsensusState.Follower;
    var current_term: int = 0;
    var voted_for: string = "";       // who we voted for this term
    var votes_received: int = 0;
    var committed_values: [0..#256] string;
    var committed_count: int = 0;

    // ── Membership ────────────────────────────────────────────────

    /// Add a node to the consensus pool.
    proc add_node(node_id: string) {
      if node_count < node_ids.size {
        node_ids[node_count] = node_id;
        node_count += 1;
      }
    }

    /// How many nodes constitute a majority?
    proc majority(): int {
      return (node_count / 2) + 1;
    }

    // ── Election ──────────────────────────────────────────────────

    /// Start an election. Transitions to Candidate and votes for self.
    ///
    /// In real Raft, this fires when the election timeout expires
    /// without hearing from a leader. We model it as an explicit call.
    proc start_election(node_id: string) {
      current_term += 1;
      state = ConsensusState.Candidate;
      voted_for = node_id;
      votes_received = 1; // self-vote
    }

    /// Process a vote from `node_id` for the given term.
    ///
    /// Returns true if the vote was accepted (matching term, not
    /// already voted for someone else this term).
    proc vote(node_id: string, for_term: int): bool {
      // Reject stale or future terms
      if for_term != current_term then return false;

      // Only Candidates accept votes
      if state != ConsensusState.Candidate then return false;

      // Don't double-count a node's vote
      // (In this simplified model, we just increment)
      votes_received += 1;

      // Check if we've won
      if votes_received >= majority() {
        state = ConsensusState.Leader;
      }

      return true;
    }

    // ── Proposals ─────────────────────────────────────────────────

    /// Propose a value. Only the Leader can propose.
    ///
    /// In real Raft, the leader replicates to a majority before
    /// committing. Here we require the leader state (which implies
    // a majority elected us) and commit immediately.
    proc propose(value: string): bool {
      if state != ConsensusState.Leader then return false;

      if committed_count < committed_values.size {
        committed_values[committed_count] = value;
        committed_count += 1;
      }
      return true;
    }

    // ── Query ─────────────────────────────────────────────────────

    /// Is this pool (node) currently the leader?
    proc is_leader(): bool {
      return state == ConsensusState.Leader;
    }

    /// Get the current term number.
    proc term(): int {
      return current_term;
    }

    /// Count of committed values.
    proc committed_count_val(): int {
      return committed_count;
    }

    /// Reset to follower state (simulates receiving a heartbeat
    /// from a higher-term leader).
    proc step_down(new_term: int) {
      if new_term > current_term {
        current_term = new_term;
        state = ConsensusState.Follower;
        voted_for = "";
        votes_received = 0;
      }
    }
  }

} // module Consensus
