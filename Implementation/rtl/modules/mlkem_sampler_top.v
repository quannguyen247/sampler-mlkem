`timescale 1ns / 1ps
`include "mlkem_sampler_defs.vh"

module mlkem_sampler_top (
    input wire clk,
    input wire rst_n,

    // Mode control
    input wire [`MLKEM_SAMPLER_MODE_WIDTH-1:0] mode,

    // Input byte stream
    input wire byte_valid,
    input wire [7:0] byte_in,
    output wire byte_ready,

    // Output coefficient stream
    input wire coeff_ready,
    output wire coeff_valid,
    output wire [`MLKEM_COEFF_WIDTH-1:0] coeff_out,
    output wire coeff_last,

    // Global control
    input wire start,
    output wire busy,
    output wire done
);

    reg [`MLKEM_SAMPLER_MODE_WIDTH-1:0] mode_r;
    reg active_r;

    wire mode_supported;
    wire ntt_selected;
    wire cbd_selected;
    wire ntt_start;
    wire cbd_start;
    wire selected_done;

    wire ntt_byte_ready;
    wire ntt_coeff_valid;
    wire [`MLKEM_COEFF_WIDTH-1:0] ntt_coeff_out;
    wire ntt_coeff_last;
    wire ntt_done;

    wire cbd_byte_ready;
    wire cbd_coeff_valid;
    wire [`MLKEM_COEFF_WIDTH-1:0] cbd_coeff_out;
    wire cbd_coeff_last;
    wire cbd_done;

    sample_ntt u_sample_ntt (
        .clk(clk),
        .rst_n(rst_n),
        .byte_valid(byte_valid && active_r && ntt_selected),
        .byte_in(byte_in),
        .byte_ready(ntt_byte_ready),
        .coeff_ready(coeff_ready && active_r && ntt_selected),
        .coeff_valid(ntt_coeff_valid),
        .coeff_out(ntt_coeff_out),
        .coeff_last(ntt_coeff_last),
        .start(ntt_start),
        .busy(),
        .done(ntt_done)
    );

    sample_poly_cbd u_sample_poly_cbd (
        .clk(clk),
        .rst_n(rst_n),
        .eta((mode == `MLKEM_SAMPLER_MODE_CBD_ETA3) ? 2'd3 : 2'd2),
        .byte_valid(byte_valid && active_r && cbd_selected),
        .byte_in(byte_in),
        .byte_ready(cbd_byte_ready),
        .coeff_ready(coeff_ready && active_r && cbd_selected),
        .coeff_valid(cbd_coeff_valid),
        .coeff_out(cbd_coeff_out),
        .coeff_last(cbd_coeff_last),
        .start(cbd_start),
        .busy(),
        .done(cbd_done)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            mode_r <= `MLKEM_SAMPLER_MODE_NTT;
            active_r <= 1'b0;
        end else begin
            if (!active_r) begin
                if (start && mode_supported) begin
                    mode_r <= mode;
                    active_r <= 1'b1;
                end
            end else if (selected_done) begin
                active_r <= 1'b0;
            end
        end
    end

    assign mode_supported = (mode == `MLKEM_SAMPLER_MODE_NTT) ||
                            (mode == `MLKEM_SAMPLER_MODE_CBD_ETA2) ||
                            (mode == `MLKEM_SAMPLER_MODE_CBD_ETA3);
    assign ntt_selected = (mode_r == `MLKEM_SAMPLER_MODE_NTT);
    assign cbd_selected = (mode_r == `MLKEM_SAMPLER_MODE_CBD_ETA2) ||
                          (mode_r == `MLKEM_SAMPLER_MODE_CBD_ETA3);
    assign ntt_start = start && !active_r &&
                       (mode == `MLKEM_SAMPLER_MODE_NTT);
    assign cbd_start = start && !active_r &&
                       ((mode == `MLKEM_SAMPLER_MODE_CBD_ETA2) ||
                        (mode == `MLKEM_SAMPLER_MODE_CBD_ETA3));
    assign selected_done = ntt_selected ? ntt_done : cbd_done;

    assign byte_ready = active_r &&
                        (ntt_selected ? ntt_byte_ready : cbd_byte_ready);
    assign coeff_valid = active_r &&
                         (ntt_selected ? ntt_coeff_valid : cbd_coeff_valid);
    assign coeff_out = ntt_selected ? ntt_coeff_out : cbd_coeff_out;
    assign coeff_last = active_r &&
                        (ntt_selected ? ntt_coeff_last : cbd_coeff_last);
    assign busy = active_r;
    assign done = active_r && selected_done;

endmodule
