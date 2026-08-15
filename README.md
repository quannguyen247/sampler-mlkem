# ML-KEM Sampler FPGA / IP Core

ML-KEM Sampler is a synthesizable Verilog RTL implementation of the two
sampling primitives required by ML-KEM:

- `SampleNTT`, using rejection sampling over an open-ended SHAKE128 byte stream
- `SamplePolyCBD`, supporting both eta = 2 and eta = 3

The design accepts one byte at a time and emits one coefficient at a time.
Both interfaces use ready/valid handshakes, so input and output backpressure do
not change the sampled polynomial.

## Key Facts

- Unified top design:
  [Implementation/rtl/modules/mlkem_sampler_top.v](Implementation/rtl/modules/mlkem_sampler_top.v)
- NTT rejection sampler:
  [Implementation/rtl/modules/sample_ntt.v](Implementation/rtl/modules/sample_ntt.v)
- Centered binomial sampler:
  [Implementation/rtl/modules/sample_poly_cbd.v](Implementation/rtl/modules/sample_poly_cbd.v)
- Shared definitions:
  [Implementation/rtl/utils/mlkem_sampler_defs.vh](Implementation/rtl/utils/mlkem_sampler_defs.vh)
- Deterministic vector generator:
  [Implementation/vector/sampler_test_vectors.py](Implementation/vector/sampler_test_vectors.py)
- Testbench:
  [Implementation/testbench/tb_mlkem_sampler.sv](Implementation/testbench/tb_mlkem_sampler.sv)

No Vivado project, AXI wrapper, Keccak core, codec, sequencer, or integrated
ML-KEM accelerator is included.

## Supported Modes

| Mode | Input | Output |
|---|---|---|
| `MLKEM_SAMPLER_MODE_NTT` | Open-ended SHAKE128 byte stream | 256 coefficients in `[0, 3328]` |
| `MLKEM_SAMPLER_MODE_CBD_ETA2` | Exactly 128 bytes | 256 coefficients modulo 3329 |
| `MLKEM_SAMPLER_MODE_CBD_ETA3` | Exactly 192 bytes | 256 coefficients modulo 3329 |

Mode values are defined in
[Implementation/rtl/utils/mlkem_sampler_defs.vh](Implementation/rtl/utils/mlkem_sampler_defs.vh).

## Interface Protocol

Assert `start` for one clock while `busy` is low. The top latches `mode` and
then accepts input through `byte_valid`, `byte_ready`, and `byte_in`.

Sampled coefficients are transferred through `coeff_valid`, `coeff_ready`, and
`coeff_out`. `coeff_last` is asserted with coefficient 255. The output remains
stable while `coeff_valid` is high and `coeff_ready` is low.

`done` is a one-cycle pulse after the final coefficient is accepted. Unsupported
mode value `2'b11` is ignored.

## RTL Architecture

### `sample_ntt.v`

The rejection sampler reads three bytes and derives two 12-bit candidates:

```text
d1 = b0 + 256 * (b1 & 0x0f)
d2 = (b1 >> 4) + 16 * b2
```

It emits `d1` before `d2`, accepts only candidates below 3329, and continues
requesting bytes until exactly 256 coefficients have been transferred.

### `sample_poly_cbd.v`

The CBD sampler interprets bytes in little-endian bit order:

- eta = 2: one byte produces two coefficients
- eta = 3: three bytes produce four coefficients

Each signed result `a - b` is represented canonically modulo 3329.

### `mlkem_sampler_top.v`

The unified top instantiates one `SampleNTT` engine and one `SamplePolyCBD`
engine. It latches the requested mode and routes only the selected engine to the
external byte and coefficient streams.

## Verification

Generate deterministic vectors:

```powershell
python Implementation/vector/sampler_test_vectors.py
```

The testbenches cover:

- `SampleNTT` candidate ordering and rejection at the `q = 3329` boundary
- open-ended input after long rejection runs
- output stability under backpressure
- eta = 2 and eta = 3 CBD bit ordering
- exactly 256 output coefficients
- `coeff_last`, `busy`, and one-cycle `done` behavior
- routing through all three unified-top modes

Current testbench top:

- `tb_mlkem_sampler`

## Directory Layout

- `Implementation/rtl/modules/` - synthesizable RTL modules
- `Implementation/rtl/utils/` - shared definitions
- `Implementation/testbench/` - ModelSim testbenches
- `Implementation/vector/` - Python vector generator and generated vectors

## Limitations

- The input stream must contain enough bytes to complete the requested sample.
- No input `last` signal is required or consumed.
- Synthesis, implementation, timing, and utilization must be measured in the
  target integration project.
