import sys
from pathlib import Path

VECTORS = Path(__file__).resolve().parent
Q = 3329
COEFF_COUNT = 256
RNG_SEED = 0x53414D50

MODE_NTT = 0
MODE_CBD_ETA2 = 1
MODE_CBD_ETA3 = 2


def xorshift32(state):
    state = (state ^ (state << 13)) & 0xFFFFFFFF
    state = (state ^ (state >> 17)) & 0xFFFFFFFF
    return (state ^ (state << 5)) & 0xFFFFFFFF


def encode_ntt_group(d1, d2):
    return bytes((
        d1 & 0xFF,
        ((d1 >> 8) & 0x0F) | ((d2 & 0x0F) << 4),
        (d2 >> 4) & 0xFF,
    ))


def sample_ntt(data):
    coefficients = []
    offset = 0

    while len(coefficients) < COEFF_COUNT:
        if offset + 3 > len(data):
            raise ValueError("SampleNTT input ended before 256 coefficients")

        b0, b1, b2 = data[offset:offset + 3]
        offset += 3
        d1 = b0 + 256 * (b1 & 0x0F)
        d2 = (b1 >> 4) + 16 * b2

        if d1 < Q:
            coefficients.append(d1)
            if len(coefficients) == COEFF_COUNT:
                break

        if d2 < Q:
            coefficients.append(d2)

    return coefficients, offset


def sample_poly_cbd(data, eta):
    expected_bytes = 64 * eta
    if len(data) != expected_bytes:
        raise ValueError(f"CBD eta={eta} requires {expected_bytes} bytes")

    value = int.from_bytes(data, "little")
    coefficients = []

    for index in range(COEFF_COUNT):
        bit_offset = 2 * eta * index
        a = 0
        b = 0

        for bit in range(eta):
            a += (value >> (bit_offset + bit)) & 1
            b += (value >> (bit_offset + eta + bit)) & 1

        coefficients.append((a - b) % Q)

    return coefficients


def deterministic_bytes(length, seed):
    state = RNG_SEED ^ seed
    output = bytearray()

    for _ in range(length):
        state = xorshift32(state)
        output.append(state & 0xFF)

    return bytes(output)


def build_ntt_cases():
    cases = []

    directed = bytearray()
    directed.extend(encode_ntt_group(0x234, 0x561))
    directed.extend(encode_ntt_group(1, 4095))
    directed.extend(encode_ntt_group(4095, 4095))
    directed.extend(encode_ntt_group(4095, 0))
    directed.extend(encode_ntt_group(2, 4095))

    for index in range(125):
        directed.extend(encode_ntt_group((17 * index + 3) % Q,
                                         (29 * index + 7) % Q))

    directed.extend(encode_ntt_group(1234, 2345))
    cases.append(bytes(directed))

    random_data = bytearray()
    state = RNG_SEED ^ 0x1001
    while True:
        state = xorshift32(state)
        random_data.append(state & 0xFF)
        coefficients, consumed = sample_ntt_if_complete(random_data)
        if coefficients is not None:
            cases.append(bytes(random_data[:consumed]))
            break

    rejection_run = bytearray(encode_ntt_group(4095, 4095) * 64)
    for index in range(128):
        rejection_run.extend(encode_ntt_group((31 * index) % Q,
                                              (47 * index + 1) % Q))
    cases.append(bytes(rejection_run))

    boundary = bytearray()
    boundary.extend(encode_ntt_group(Q - 1, Q))
    boundary.extend(encode_ntt_group(Q, Q - 1))
    boundary.extend(encode_ntt_group(0, 4095))
    boundary.extend(encode_ntt_group(4095, 0))
    for index in range(126):
        boundary.extend(encode_ntt_group((Q - 1 - index) % Q,
                                        (index + 1) % Q))
    cases.append(bytes(boundary))

    return cases


def sample_ntt_if_complete(data):
    coefficients = []
    offset = 0

    while offset + 3 <= len(data):
        b0, b1, b2 = data[offset:offset + 3]
        offset += 3
        d1 = b0 + 256 * (b1 & 0x0F)
        d2 = (b1 >> 4) + 16 * b2

        if d1 < Q:
            coefficients.append(d1)
            if len(coefficients) == COEFF_COUNT:
                return coefficients, offset

        if d2 < Q:
            coefficients.append(d2)
            if len(coefficients) == COEFF_COUNT:
                return coefficients, offset

    return None, None


def build_cbd_cases():
    cases = []

    for eta, mode in ((2, MODE_CBD_ETA2), (3, MODE_CBD_ETA3)):
        length = 64 * eta
        cases.append((mode, bytes(length)))
        cases.append((mode, bytes([0xFF] * length)))
        cases.append((mode, bytes((index * 37 + eta * 11) & 0xFF
                                  for index in range(length))))
        cases.append((mode, deterministic_bytes(length, 0x2000 + eta)))

    return cases


def write_mem(path, values, width):
    hex_width = (width + 3) // 4
    with open(path, "w") as file:
        for value in values:
            file.write(f"{value:0{hex_width}x}\n")


def generate_vectors():
    ntt_inputs = []
    ntt_outputs = []
    ntt_meta = []

    for data in build_ntt_cases():
        coefficients, consumed = sample_ntt(data)
        if consumed != len(data):
            raise ValueError("SampleNTT case contains unused trailing bytes")

        input_offset = len(ntt_inputs)
        output_offset = len(ntt_outputs)
        ntt_inputs.extend(data)
        ntt_outputs.extend(coefficients)
        ntt_meta.append(input_offset |
                        (len(data) << 16) |
                        (output_offset << 32))

    cbd_inputs = []
    cbd_outputs = []
    cbd_meta = []

    for mode, data in build_cbd_cases():
        eta = 2 if mode == MODE_CBD_ETA2 else 3
        coefficients = sample_poly_cbd(data, eta)
        input_offset = len(cbd_inputs)
        output_offset = len(cbd_outputs)
        cbd_inputs.extend(data)
        cbd_outputs.extend(coefficients)
        cbd_meta.append(mode |
                        (input_offset << 2) |
                        (len(data) << 18) |
                        (output_offset << 34))

    write_mem(VECTORS / "sample_ntt_input.mem", ntt_inputs, 8)
    write_mem(VECTORS / "sample_ntt_output.mem", ntt_outputs, 12)
    write_mem(VECTORS / "sample_ntt_cases.mem", ntt_meta, 48)
    write_mem(VECTORS / "sample_cbd_input.mem", cbd_inputs, 8)
    write_mem(VECTORS / "sample_cbd_output.mem", cbd_outputs, 12)
    write_mem(VECTORS / "sample_cbd_cases.mem", cbd_meta, 50)

    (VECTORS / "sampler_tv_spec.txt").write_text(
        f"ntt_case_count={len(ntt_meta)}\n"
        f"ntt_input_count={len(ntt_inputs)}\n"
        f"ntt_output_count={len(ntt_outputs)}\n"
        f"cbd_case_count={len(cbd_meta)}\n"
        f"cbd_input_count={len(cbd_inputs)}\n"
        f"cbd_output_count={len(cbd_outputs)}\n"
    )

    return len(ntt_meta), len(cbd_meta)


def clear_vectors():
    for path in VECTORS.glob("sample_*.mem"):
        path.unlink()

    spec = VECTORS / "sampler_tv_spec.txt"
    if spec.exists():
        spec.unlink()


def main():
    if len(sys.argv) > 1 and sys.argv[1].lower() == "clear":
        clear_vectors()
        print("Cleared sampler vectors.")
        return 0

    ntt_count, cbd_count = generate_vectors()
    print(f"Generated {ntt_count} SampleNTT cases and {cbd_count} CBD cases.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
