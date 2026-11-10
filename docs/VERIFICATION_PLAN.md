# ML-KEM Sampler Verification Plan

Document status: verification requirements and closure plan  
Revision: 0.1  
Date: 2026-08-12

## 1. Purpose

This plan defines UVM-ready verification and closure for the behavior in
[`../SPEC.md`](../SPEC.md). It supports block-level research, FPGA
prototyping, and ASIC-quality DV. Planned items are not current completion
claims.

The environment should follow IEEE 1800.2-compatible UVM methodology and keep
tool-specific integrations outside reusable components.

## 2. Verification objectives

| ID | Objective |
|---|---|
| SAM-DV-001 | Prove bit-exact FIPS 203 `SampleNTT` candidate parsing, rejection, ordering, and termination. |
| SAM-DV-002 | Prove bit-exact FIPS 203 `SamplePolyCBD` behavior for `eta=2` and `eta=3`. |
| SAM-DV-003 | Prove exactly 256 accepted coefficients and correct `coeff_last` behavior. |
| SAM-DV-004 | Prove byte-input and coefficient-output handshake behavior under arbitrary legal stalls. |
| SAM-DV-005 | Prove reset, unsupported mode, repeated start, completion, and return-to-idle behavior. |
| SAM-DV-006 | Close functional, assertion, code, FSM, and toggle coverage with reviewed exclusions only. |
| SAM-DV-007 | Make every failure reproducible by seed, test, RTL revision, and golden-model revision. |

## 3. Existing baseline assets

The repository currently contains:

- `sampler_test_vectors.py`, with independent Python implementations of
  `sample_ntt` and `sample_poly_cbd`;
- four SampleNTT cases totaling 1839 input bytes and 1024 expected
  coefficients;
- eight CBD cases totaling 1280 input bytes and 2048 expected coefficients;
- `tb_mlkem_sampler.sv`, which injects periodic input/output stalls, compares
  coefficients, checks output stability, checks `coeff_last`, checks idle
  return, and checks unsupported mode.

These are regression seeds, not verification closure. No UVM, SVA, formal
proof, or coverage database is checked in.

## 4. UVM architecture

### 4.1 Environment

`mlkem_sampler_env` shall contain:

- `sampler_ctrl_agent`: drives/monitors `start`, `mode`, reset, `busy`, and
  `done`;
- `sampler_byte_agent`: byte-stream driver and monitor;
- `sampler_coeff_agent`: ready driver and output monitor;
- `sampler_scoreboard`: predicts accepted coefficients and completion;
- `sampler_virtual_sequencer`: coordinates mode, byte source, backpressure,
  reset, and negative scenarios;
- `sampler_coverage`: samples functional and protocol coverage;
- SVA bind modules for top, SampleNTT, and CBD interfaces.

The same agents shall support active and passive modes for subsystem
integration.

### 4.2 Transactions

`sampler_operation_item` shall contain:

- requested mode;
- ordered byte stream or deterministic byte-source object;
- source-gap and sink-stall distributions;
- optional reset or illegal-start injection;
- expected coefficient list and expected bytes consumed;
- expected completion or expected non-start classification.

Monitor transactions shall be reconstructed from accepted transfers only.
The byte driver shall support on-demand extension for rejection-heavy
SampleNTT tests.

### 4.3 Configuration

Configuration shall define:

- active/passive agents;
- timeout policy;
- maximum generated SampleNTT bytes for bounded random tests;
- golden-model backend and revision;
- assertion, functional coverage, and code coverage enablement;
- error injection and X-propagation policy.

Timeouts shall distinguish a DUT deadlock from a deliberately starved input
source.

## 5. Golden models

At least one independent Python or C model shall implement the FIPS 203
pseudocode without copying RTL state-machine structure.

Required model behavior:

- explicit three-byte SampleNTT parsing;
- candidate order `d1` then `d2`;
- rejection at `candidate >= 3329`;
- stop after exactly 256 accepted candidates and report bytes consumed;
- little-endian `BytesToBits` interpretation for CBD;
- `eta=2` and `eta=3` population-count difference;
- canonical modulo-`q` output;
- deterministic vector and seed replay.

Before signoff, the model shall be cross-checked against an independent
standards-conformant ML-KEM implementation or published known-answer
intermediates. A model that duplicates RTL expressions alone is insufficient.

## 6. Scoreboard rules

- Consume source bytes only on `byte_valid && byte_ready`.
- Compare coefficients only on `coeff_valid && coeff_ready`.
- Predict and compare all 256 outputs in order.
- Check `coeff_last` is high only with output index 255.
- Check exact input-byte consumption for completed directed cases.
- For SampleNTT, allow legal variable input length and stop prediction at the
  group that yields coefficient 255.
- For CBD, require exactly 128 bytes for `eta=2` and 192 bytes for `eta=3`.
- Flush all pending predictions on reset.
- For unsupported mode, expect no active transaction and no output.
- Check that `done` follows the last accepted coefficient and that the
  interface returns to idle on the following active clock edge.

## 7. Test and sequence matrix

| Test family | Required content |
|---|---|
| Smoke | One SampleNTT, CBD eta=2, and CBD eta=3 operation. |
| SampleNTT directed | Candidates 0, 1, `q-1`, `q`, 4095; all accept/reject combinations in a pair. |
| SampleNTT rejection | Long rejected runs at beginning, middle, and before coefficient 255. |
| SampleNTT random | Random byte streams extended until 256 accepted coefficients. |
| CBD basis | All-zero, all-one, walking-one, walking-zero, alternating, and deterministic random inputs. |
| CBD exhaustive local | Exhaust all 4-bit eta=2 coefficient patterns and all 6-bit eta=3 coefficient patterns. |
| Backpressure | Independent random input gaps and output stalls, including long bounded stalls at every output index. |
| Reset | Reset in every reachable state, at every input-byte position, and at first/middle/last output. |
| Control negative | Unsupported mode, start while active, start during done, mode changes after start, valid outside ready. |
| Completion | Check output count, last flag, done pulse, busy/done overlap, and clean idle return. |
| Starvation | Pause input indefinitely for bounded observation, then resume without data loss. |
| Integration | Stream bytes from the Keccak/XOF block and compare sampled polynomials to the system model. |
| X-propagation | Dedicated unknown-control/data robustness tests; diagnostic only outside legal input. |

Submodule-level tests shall also characterize `sample_poly_cbd` behavior for
an `eta` value other than 3, which the current RTL maps to eta=2. Top-level
legal modes remain only those in the specification.

## 8. Assertions

Bind at least the following properties:

- synchronous reset returns every FSM to idle;
- top `active_r` starts only for a supported idle request;
- unsupported mode never asserts busy/ready/valid/done;
- byte data remains an environment assumption while valid and not ready;
- output data and last remain stable while valid and not ready;
- coefficient count increments only on accepted output;
- `coeff_last` iff current accepted/output-visible index is 255;
- no more than 256 outputs occur;
- `done` is one cycle and is accompanied by `busy`;
- busy clears on the edge after done;
- SampleNTT byte order is exactly three accepted bytes per candidate pair;
- rejected candidates never reach the output interface;
- CBD group index and coefficient index remain in legal ranges;
- FSM encodings are one-hot and transitions are legal;
- no unknown output/control values occur after reset for legal stimulus.

Formal assumptions shall be separated from DUT guarantees. Liveness properties
shall assume eventual input validity and output readiness.

## 9. Functional coverage

Required coverpoints and crosses:

- mode, including unsupported;
- SampleNTT candidate class: zero, interior, `q-1`, `q`, maximum;
- accepted/rejected pair pattern: AA, AR, RA, RR;
- rejection-run length buckets;
- group yielding coefficient 255 and whether it is `d1` or `d2`;
- CBD eta and local difference from `-eta` through `+eta`;
- byte pattern class;
- coefficient index buckets including 0 and 255;
- source-gap and sink-stall length;
- reset state and group/byte/coefficient position;
- start accepted versus ignored;
- FSM states and transitions;
- mode x backpressure;
- mode x reset-state;
- eta x centered-difference;
- candidate pattern x terminal position.

Unreachable bins require reviewed proof or rationale.

## 10. Code and structural coverage

Closure targets:

- FSM state and legal-transition coverage: 100%.
- Functional coverage: 100% of planned, non-waived bins.
- Assertion coverage: every assertion exercised; all failures resolved.
- Statement/line coverage: at least 95%.
- Branch/condition coverage: at least 90%.
- Toggle coverage: at least 90% on applicable non-constant design signals.

Defensive defaults and structurally unreachable branches may be excluded only
through a reviewed exclusion file tied to the RTL revision.

## 11. Regression tiers

| Tier | Trigger | Content | Gate |
|---|---|---|---|
| T0 | Every change | Compile, lint subset, three-mode smoke | Zero errors |
| T1 | RTL/DV pull request | Existing vectors, protocol stalls, unsupported mode, reset | Zero failures |
| T2 | Nightly | Constrained-random streams, rejection stress, coverage merge | No unexplained failures |
| T3 | Release candidate | Large seed campaign, formal, X-prop, gate-level subset | Coverage and proof closure |
| T4 | Integration release | Keccak-to-sampler streams, KV260/ASIC netlist regressions | Signed release report |

Archive test, seed, simulator/tool version, compile options, RTL revision,
golden-model revision, assertion summary, and coverage database.

## 12. Formal verification

Recommended proofs:

- output stability and no loss/duplication under backpressure;
- exactly 256 outputs under fair input/output assumptions;
- terminal `coeff_last` and done ordering;
- unsupported mode non-start;
- legal FSM state/transition invariants;
- SampleNTT rejected candidates are never emitted;
- CBD local mapping equivalence for every 4-bit and 6-bit coefficient pattern;
- reset recovery from every state.

Liveness for SampleNTT requires an assumption that the source eventually
provides enough candidates below `q`.

## 13. Closure and waiver rules

DV closure requires:

- each `SAM-FUNC`, `SAM-IF`, and performance requirement mapped to a passing
  test or proof;
- all planned functional bins covered or formally waived;
- coverage targets met;
- zero unresolved UVM errors, scoreboard mismatches, assertion failures, or
  unexpected timeouts;
- exact seed replay and archived metadata;
- independent golden-model and endian review;
- no open severity-1 or severity-2 defects.

Each waiver shall contain requirement/coverage ID, owner, rationale, impact,
evidence, expiration condition, and approving reviewer. A tool limitation
requires an alternate check.

Functional closure does not establish randomness quality, entropy quality,
side-channel resistance, fault resistance, or complete ML-KEM compliance.

## 14. Requirement traceability

| Spec IDs | Primary verification components |
|---|---|
| SAM-FUNC-001..004 | SampleNTT sequences, model, scoreboard, count/order SVA |
| SAM-FUNC-005..008 | CBD exhaustive-local/random sequences, model, scoreboard |
| SAM-FUNC-009 | Unsupported-mode sequence and non-start SVA |
| SAM-IF-001..010 | Protocol agents, negative/reset sequences, SVA |
| SAM-PERF-001..004 | Cycle monitor and formula-based prediction |
| SAM-SEC-001..005 | Security/integration review; not functional coverage |

## 15. Current factual limitations

- No UVM environment, SVA bind layer, formal proof, or coverage database is
  present.
- Existing vectors cover four SampleNTT and eight CBD cases only.
- No integrated Keccak-to-sampler regression is present.
- Gate-level simulation, X-propagation, coverage closure, and independent
  model cross-certification are **UNVERIFIED**.
