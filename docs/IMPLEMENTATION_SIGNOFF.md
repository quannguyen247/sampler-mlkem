# ML-KEM Sampler Implementation Signoff Plan

Document status: required implementation evidence  
Revision: 0.1  
Date: 2026-08-12

## 1. Purpose

This document defines evidence required for FPGA prototyping on the AMD Kria
KV260 Starter Kit with K26 SOM and for a generic ASIC flow. It is not a report
of completed signoff.

Unless a dated release report is cited, timing, utilization, power, CDC/RDC,
DRC, LEC, DFT, and physical-verification results are **UNVERIFIED**.

See [`../SPEC.md`](../SPEC.md) for the functional contract and
[`VERIFICATION_PLAN.md`](VERIFICATION_PLAN.md) for DV closure.

## 2. Common release inputs

Every run shall archive:

- immutable RTL revision and source manifest;
- selected top module;
- include paths and source order;
- constraints and integration wrapper revision;
- target device/library and tool versions;
- clocks, resets, I/O assumptions, operating conditions, and derates;
- synthesis, implementation, and signoff scripts;
- waiver file, reports, logs, netlists, and checksums.

Results for `mlkem_sampler_top`, `sample_ntt`, and `sample_poly_cbd` shall be
identified separately.

## 3. Pre-implementation gates

### 3.1 RTL and elaboration

- Elaborate every supported top and mode.
- Treat implicit nets, truncation, signedness ambiguity, inferred latches,
  undriven/multiply driven signals, combinational loops, and out-of-range
  accesses as errors unless waived.
- Review synthesis of modulo-`q` subtraction, population count logic,
  comparators, and one-hot FSMs.
- Confirm reset behavior matches the active-low synchronous specification.

### 3.2 Lint

Release lint requires:

- zero unwaived errors;
- zero unwaived high-severity warnings;
- reviewed width, reset, FSM, unreachable-code, constant, and X-propagation
  findings;
- waivers tied to rule, object, RTL revision, owner, and approval.

### 3.3 CDC and RDC

The standalone RTL has one clock domain. Analysis shall prove:

- all state elements use the intended clock;
- no generated or implicit clocks exist;
- reset release follows the integration reset strategy;
- wrapper-introduced CDC/RDC uses approved synchronization;
- no false path or asynchronous clock declaration hides an unsafe crossing.

## 4. FPGA flow: AMD Kria KV260/K26

### 4.1 Target definition

The prototype target is the AMD Kria KV260 Starter Kit with K26 SOM. Exact
Vivado board/device part, speed grade, Vivado release, platform clocks, and
wrapper are **TBD** and shall be recorded before implementation.

The repository currently contains no XDC. No target clock, I/O delay, or
timing result is established.

### 4.2 Out-of-context flow

The OOC flow shall:

1. Elaborate `mlkem_sampler_top` and, where useful, both submodules.
2. Apply a reviewed clock to `clk`.
3. Define input/output delays or documented virtual-clock assumptions.
4. Constrain synchronous reset behavior.
5. report unconstrained paths and ignored constraints.
6. Run synthesis and OOC placement/routing.
7. Produce utilization, methodology DRC, timing, and power reports.

### 4.3 Integrated KV260 flow

The native byte/coefficient handshake is not AXI. A separately specified
wrapper is required for processor-controlled hardware testing. Integrated
signoff shall cover:

- processing-system/programmable-logic clocks and resets;
- AXI/DMA/stream wrapper protocol and buffering;
- CDC/RDC through the wrapper;
- software-visible control/status and timeout behavior;
- byte-order and coefficient-order preservation;
- ability to continue SampleNTT input until completion;
- hardware comparison against versioned FIPS 203 golden data;
- bitstream, software, and reproducible board-test logs.

The wrapper, software, and platform design are outside the current repo.

### 4.4 FPGA implementation evidence

Required post-route evidence:

- synthesis and routed utilization by hierarchy;
- LUT, FF, SRL, LUTRAM, BRAM, URAM, and DSP counts;
- clock utilization;
- methodology DRC and implementation DRC with zero unwaived errors;
- zero unrouted or partially routed nets;
- timing summary with WNS, TNS, WHS, THS, failing endpoints, and
  unconstrained-path count;
- detailed worst setup/hold and high-fanout/reset paths;
- reviewed timing exceptions;
- power report with activity source, workload, operating assumptions, and
  confidence;
- programmed-KV260 test log.

Timing signoff requires non-negative setup and hold slack in the fully routed
release design. RTL simulation and synthesis estimates are not timing
evidence.

### 4.5 FPGA power

Use representative SAIF/VCD activity where possible. Measure/report
separately:

- idle;
- SampleNTT accept-heavy input;
- SampleNTT rejection-heavy input;
- CBD eta=2;
- CBD eta=3;
- sustained output backpressure.

Vectorless activity may be used only as a labeled low-confidence estimate.

## 5. ASIC flow

### 5.1 Technology and constraints

Define before implementation:

- process/library and voltage domains;
- PVT and RC corners;
- functional and test clocks;
- uncertainty, jitter, OCV/derates;
- floorplan utilization and congestion targets;
- I/O/package assumptions;
- reliability requirements.

These are currently **TBD**.

### 5.2 Synthesis and LEC

- Synthesize with reviewed production constraints.
- Report area by hierarchy and cell class.
- Review comparator, population-count, and modulo subtraction mapping.
- Run RTL-to-synthesis logical equivalence.
- Resolve all non-equivalent points or approve explicit waivers.
- Archive scripts, compare points, reports, and logs.

### 5.3 STA and MMMC

- Define functional, scan-shift, scan-capture, and low-power modes as
  applicable.
- Analyze all required PVT/RC corners with MMMC.
- Close setup, hold, recovery, removal, minimum pulse width, clock gating,
  transition, capacitance, and fanout checks.
- Review every false-path and multicycle exception.
- Perform final STA with extracted post-route parasitics.

### 5.4 DFT expectations

The DFT plan shall specify:

- scan insertion and coverage targets;
- scan/test clocks and resets;
- compression and at-speed test strategy;
- boundary scan and memory BIST needs, if introduced by integration;
- ATPG stuck-at and transition coverage;
- untestable-fault review;
- secure treatment of sampled data, internal registers, debug, and test mode.

The current small register-based block has no memory macro, but integration
buffers may require MBIST. Scan access and debug policy require security
review.

### 5.5 Place, route, and physical signoff

- Establish floorplan and congestion margin.
- Complete CTS and post-CTS optimization.
- Route with zero unwaived DRC.
- Perform extracted STA and post-route equivalence.
- Complete foundry-required DRC, LVS, antenna, density, ERC, and reliability
  checks.
- Review IR drop, electromigration, crosstalk, and thermal assumptions.
- Archive GDS/OASIS, netlists, parasitics, timing models, power intent, and
  signoff reports.

### 5.6 ASIC power

Use representative activity for NTT acceptance/rejection distributions, both
CBD modes, idle, and backpressure. Report dynamic, leakage, clock, and
state-dependent power. Peak-current analysis shall include high-toggle input
and output conditions.

## 6. Security implementation review

Before any security claim:

- identify whether sampled bytes and coefficients are public, secret, or
  ephemeral in each enclosing operation;
- define reset/abort/completion zeroization;
- evaluate data-dependent SampleNTT runtime in system context;
- review scan, debug, readback, and lifecycle controls;
- assess power, EM, timing, and fault leakage;
- define and validate any countermeasures.

Current RTL is unmasked, has no fault detection, and has no explicit
zeroization command. No side-channel or fault-resistance claim is permitted.

## 7. Release artifacts

| Category | Required artifacts |
|---|---|
| Source | RTL manifest, constraints, wrapper parameters, scripts, revision IDs |
| DV | Regression, requirement matrix, assertions, coverage, waivers |
| FPGA | Checkpoints, utilization, DRC, routed timing, power, bitstream, board log |
| ASIC front end | Lint, CDC/RDC, synthesis, LEC, MMMC constraints and STA |
| ASIC back end | Floorplan, P&R, extracted STA, DRC/LVS/ERC, IR/EM, GDS/OASIS |
| Security | Asset/zeroization review, timing-leakage assessment, DFT/debug policy |
| Release | Versioned manifest, checksums, limitations, approvals |

## 8. Signoff gates

| Gate | Acceptance criterion | Current status |
|---|---|---|
| Functional DV | Meets `VERIFICATION_PLAN.md` closure | UNVERIFIED |
| Lint | Zero unwaived error/high-severity issue | UNVERIFIED |
| CDC/RDC | Zero unwaived structural issue | UNVERIFIED |
| FPGA synthesis | Clean elaboration and reviewed utilization | UNVERIFIED |
| FPGA implementation | Fully routed, DRC clean, setup/hold closed | UNVERIFIED |
| FPGA power | Activity-qualified report | UNVERIFIED |
| KV260 hardware | Reproducible model-versus-hardware comparison | UNVERIFIED |
| ASIC synthesis/LEC | Constraints reviewed and equivalence proven | UNVERIFIED |
| ASIC STA/MMMC | All required modes/corners closed | UNVERIFIED |
| ASIC DFT | Coverage and security policy approved | UNVERIFIED |
| ASIC physical | Foundry and reliability signoff complete | UNVERIFIED |
| Security claims | Separate analysis and validation complete | NOT CLAIMED |

No gate may be closed from source inspection, a limited RTL regression,
synthesis estimates, or reports generated for a different top, target,
constraint set, or revision.
