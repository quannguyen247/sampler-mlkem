`timescale 1ns / 1ps

module tb_mlkem_sampler;

    localparam integer TIMEOUT_CYCLES = 50000;
    localparam integer MAX_NTT_CASES = 16;
    localparam integer MAX_NTT_INPUTS = 4096;
    localparam integer MAX_NTT_OUTPUTS = 4096;
    localparam integer MAX_CBD_CASES = 16;
    localparam integer MAX_CBD_INPUTS = 4096;
    localparam integer MAX_CBD_OUTPUTS = 4096;

    logic clk, rst_n;
    logic [1:0] mode;
    logic byte_valid;
    logic [7:0] byte_in;
    logic byte_ready;
    logic coeff_ready;
    logic coeff_valid;
    logic [11:0] coeff_out;
    logic coeff_last;
    logic start, busy, done;

    logic [47:0] ntt_cases [0:MAX_NTT_CASES-1];
    logic [7:0] ntt_inputs [0:MAX_NTT_INPUTS-1];
    logic [11:0] ntt_outputs [0:MAX_NTT_OUTPUTS-1];
    logic [49:0] cbd_cases [0:MAX_CBD_CASES-1];
    logic [7:0] cbd_inputs [0:MAX_CBD_INPUTS-1];
    logic [11:0] cbd_outputs [0:MAX_CBD_OUTPUTS-1];
    logic [639:0] line_buffer;

    int ntt_case_count, ntt_input_count, ntt_output_count;
    int cbd_case_count, cbd_input_count, cbd_output_count;
    int case_idx, error_count, spec_fd;

    mlkem_sampler_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .mode(mode),
        .byte_valid(byte_valid),
        .byte_in(byte_in),
        .byte_ready(byte_ready),
        .coeff_ready(coeff_ready),
        .coeff_valid(coeff_valid),
        .coeff_out(coeff_out),
        .coeff_last(coeff_last),
        .start(start),
        .busy(busy),
        .done(done)
    );

    initial begin
        clk = 1'b0;
        forever #2.5 clk = ~clk;
    end

    task reset_dut;
    begin
        rst_n = 1'b0;
        start = 1'b0;
        byte_valid = 1'b0;
        byte_in = 8'd0;
        coeff_ready = 1'b0;
        repeat(5) @(posedge clk);
        #0.5;
        rst_n = 1'b1;
        repeat(2) @(posedge clk);
    end
    endtask

    task run_case(
        input integer sampler_mode,
        input integer input_offset,
        input integer input_length,
        input integer output_offset,
        input integer is_ntt,
        input integer test_index
    );
        integer input_index;
        integer output_index;
        integer cycles;
        reg take_byte;
        reg take_coeff;
        reg [11:0] sampled_coeff;
        reg sampled_last;
        reg hold_active;
        reg [11:0] held_coeff;
        reg held_last;
    begin
        reset_dut();
        mode = sampler_mode[1:0];
        input_index = 0;
        output_index = 0;
        cycles = 0;
        hold_active = 1'b0;
        held_coeff = 12'd0;
        held_last = 1'b0;

        @(negedge clk);
        start = 1'b1;
        @(posedge clk);
        #0.5;
        @(negedge clk);
        start = 1'b0;

        while (!done && (cycles < TIMEOUT_CYCLES)) begin
            byte_valid = (input_index < input_length) &&
                         ((cycles % 5) != 1);
            if (input_index < input_length) begin
                if (is_ntt)
                    byte_in = ntt_inputs[input_offset + input_index];
                else
                    byte_in = cbd_inputs[input_offset + input_index];
            end

            coeff_ready = ((cycles % 4) != 2);
            #0.5;
            take_byte = byte_valid && byte_ready;
            take_coeff = coeff_valid && coeff_ready;
            sampled_coeff = coeff_out;
            sampled_last = coeff_last;

            if (coeff_valid) begin
                if (sampled_last !== (output_index == 255)) begin
                    $display("FAIL: mode=%0d case=%0d coeff_last at output=%0d",
                        sampler_mode, test_index, output_index);
                    error_count = error_count + 1;
                end

                if (!coeff_ready) begin
                    if (hold_active &&
                        ((sampled_coeff !== held_coeff) ||
                         (sampled_last !== held_last))) begin
                        $display("FAIL: mode=%0d case=%0d output changed under backpressure",
                            sampler_mode, test_index);
                        error_count = error_count + 1;
                    end
                    hold_active = 1'b1;
                    held_coeff = sampled_coeff;
                    held_last = sampled_last;
                end else begin
                    hold_active = 1'b0;
                end
            end

            @(posedge clk);
            #0.5;

            if (take_byte)
                input_index = input_index + 1;

            if (take_coeff) begin
                if (is_ntt) begin
                    if (sampled_coeff !== ntt_outputs[output_offset + output_index]) begin
                        $display("FAIL: NTT case=%0d coeff=%0d expected=%03x got=%03x",
                            test_index, output_index,
                            ntt_outputs[output_offset + output_index], sampled_coeff);
                        error_count = error_count + 1;
                    end
                end else begin
                    if (sampled_coeff !== cbd_outputs[output_offset + output_index]) begin
                        $display("FAIL: CBD mode=%0d case=%0d coeff=%0d expected=%03x got=%03x",
                            sampler_mode, test_index, output_index,
                            cbd_outputs[output_offset + output_index], sampled_coeff);
                        error_count = error_count + 1;
                    end
                end

                output_index = output_index + 1;
            end

            cycles = cycles + 1;
            if (!done)
                @(negedge clk);
        end

        byte_valid = 1'b0;
        coeff_ready = 1'b0;

        if (!done || (input_index != input_length) ||
            (output_index != 256)) begin
            $display("FAIL: mode=%0d case=%0d timeout=%0d bytes=%0d/%0d coeffs=%0d",
                sampler_mode, test_index, !done,
                input_index, input_length, output_index);
            error_count = error_count + 1;
        end

        @(posedge clk);
        #0.5;
        if (done || busy || byte_ready || coeff_valid) begin
            $display("FAIL: mode=%0d case=%0d did not return cleanly to idle",
                sampler_mode, test_index);
            error_count = error_count + 1;
        end
    end
    endtask

    task test_unsupported_mode;
    begin
        reset_dut();
        mode = 2'b11;
        @(negedge clk);
        start = 1'b1;
        @(posedge clk);
        #0.5;
        start = 1'b0;
        repeat(4) @(posedge clk);
        #0.5;

        if (busy || done || byte_ready || coeff_valid) begin
            $display("FAIL: Unsupported mode was not ignored");
            error_count = error_count + 1;
        end
    end
    endtask

    string tb_file, tb_dir, tv_dir;

    function automatic string dirname(input string path);
        int slash_pos = -1;

        for (int j = 0; j < path.len(); j++)
            if ((path[j] == 8'h2F) || (path[j] == 8'h5C)) slash_pos = j;

        if (slash_pos > 0)
            return path.substr(0, slash_pos - 1);
        else if (slash_pos == 0)
            return path.substr(0, 0);
        else
            return ".";
    endfunction

    initial begin
        tb_file = `__FILE__;
        tb_dir = dirname(tb_file);
        tv_dir = {tb_dir, "/../vector"};

        error_count = 0;
        rst_n = 1'b0;
        mode = 2'd0;
        byte_valid = 1'b0;
        byte_in = 8'd0;
        coeff_ready = 1'b0;
        start = 1'b0;

        spec_fd = $fopen({tv_dir, "/sampler_tv_spec.txt"}, "r");
        if (spec_fd == 0) begin
            $display("ERROR: Cannot open %s/sampler_tv_spec.txt", tv_dir);
            $finish;
        end

        void'($fgets(line_buffer, spec_fd));
        void'($sscanf(line_buffer, "ntt_case_count=%d", ntt_case_count));
        void'($fgets(line_buffer, spec_fd));
        void'($sscanf(line_buffer, "ntt_input_count=%d", ntt_input_count));
        void'($fgets(line_buffer, spec_fd));
        void'($sscanf(line_buffer, "ntt_output_count=%d", ntt_output_count));
        void'($fgets(line_buffer, spec_fd));
        void'($sscanf(line_buffer, "cbd_case_count=%d", cbd_case_count));
        void'($fgets(line_buffer, spec_fd));
        void'($sscanf(line_buffer, "cbd_input_count=%d", cbd_input_count));
        void'($fgets(line_buffer, spec_fd));
        void'($sscanf(line_buffer, "cbd_output_count=%d", cbd_output_count));
        $fclose(spec_fd);

        if ((ntt_case_count > MAX_NTT_CASES) ||
            (ntt_input_count > MAX_NTT_INPUTS) ||
            (ntt_output_count > MAX_NTT_OUTPUTS) ||
            (cbd_case_count > MAX_CBD_CASES) ||
            (cbd_input_count > MAX_CBD_INPUTS) ||
            (cbd_output_count > MAX_CBD_OUTPUTS)) begin
            $display("ERROR: Generated vectors exceed testbench buffers");
            $finish;
        end

        $readmemh({tv_dir, "/sample_ntt_cases.mem"}, ntt_cases);
        $readmemh({tv_dir, "/sample_ntt_input.mem"}, ntt_inputs);
        $readmemh({tv_dir, "/sample_ntt_output.mem"}, ntt_outputs);
        $readmemh({tv_dir, "/sample_cbd_cases.mem"}, cbd_cases);
        $readmemh({tv_dir, "/sample_cbd_input.mem"}, cbd_inputs);
        $readmemh({tv_dir, "/sample_cbd_output.mem"}, cbd_outputs);

        for (case_idx = 0; case_idx < ntt_case_count; case_idx = case_idx + 1) begin
            run_case(
                0,
                ntt_cases[case_idx][15:0],
                ntt_cases[case_idx][31:16],
                ntt_cases[case_idx][47:32],
                1,
                case_idx
            );
        end

        for (case_idx = 0; case_idx < cbd_case_count; case_idx = case_idx + 1) begin
            run_case(
                cbd_cases[case_idx][1:0],
                cbd_cases[case_idx][17:2],
                cbd_cases[case_idx][33:18],
                cbd_cases[case_idx][49:34],
                0,
                case_idx
            );
        end

        test_unsupported_mode();

        $display(">>> ML-KEM SAMPLER PASSED: %0d NTT CASES, %0d CBD CASES (%0d ERRORS)",
            ntt_case_count, cbd_case_count, error_count);
        $finish;
    end

endmodule
