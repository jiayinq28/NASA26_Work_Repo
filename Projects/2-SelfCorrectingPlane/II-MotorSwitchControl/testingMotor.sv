`default_nettype none

module motot_top #(
    parameter int CLK_HZ       = 100_000_000,
    parameter int PWM_HZ       = 50,          // 20 ms frame
    parameter int MIN_US       = 1000,        // 1.0 ms -> 0 deg
    parameter int MAX_US       = 2000,        // 2.0 ms -> 180 deg
    parameter int SWEEP_MS     = 2000         // full end-to-end sweep time
) (
    input  wire  clk,
    input  wire  rst,          // sync, active high
    output logic servo_pwm
);

    // Derived constants (all in clk cycles)
    localparam int PERIOD_CYC = CLK_HZ / PWM_HZ;                 // 2,000,000
    localparam int MIN_CYC    = (CLK_HZ / 1_000_000) * MIN_US;   // 100,000
    localparam int MAX_CYC    = (CLK_HZ / 1_000_000) * MAX_US;   // 200,000
    localparam int SPAN_CYC   = MAX_CYC - MIN_CYC;               // 100,000

    // Pulse width step per PWM frame so a one-way sweep takes SWEEP_MS
    localparam int FRAMES_PER_SWEEP = (SWEEP_MS * PWM_HZ) / 1000; // 100
    localparam int STEP_CYC         = SPAN_CYC / FRAMES_PER_SWEEP; // 1,000

    logic [$clog2(PERIOD_CYC)-1:0] period_cnt;
    logic [$clog2(MAX_CYC+STEP_CYC)-1:0] pulse_cyc;   // current pulse width
    logic dir;                                        // 0 = up, 1 = down

    wire frame_end = (period_cnt == PERIOD_CYC - 1);

    // 20 ms frame counter
    always_ff @(posedge clk) begin
        if (rst)            period_cnt <= '0;
        else if (frame_end) period_cnt <= '0;
        else                period_cnt <= period_cnt + 1'b1;
    end

    // Update pulse width once per frame (glitch-free: only at frame boundary)
    always_ff @(posedge clk) begin
        if (rst) begin
            pulse_cyc <= MIN_CYC[$bits(pulse_cyc)-1:0];
            dir       <= 1'b0;
        end else if (frame_end) begin
            if (!dir) begin
                if (pulse_cyc + STEP_CYC >= MAX_CYC) begin
                    pulse_cyc <= MAX_CYC[$bits(pulse_cyc)-1:0];
                    dir       <= 1'b1;
                end else
                    pulse_cyc <= pulse_cyc + STEP_CYC;
            end else begin
                if (pulse_cyc <= MIN_CYC + STEP_CYC) begin
                    pulse_cyc <= MIN_CYC[$bits(pulse_cyc)-1:0];
                    dir       <= 1'b0;
                end else
                    pulse_cyc <= pulse_cyc - STEP_CYC;
            end
        end
    end

    // Registered output - no combinational glitches on the pin
    always_ff @(posedge clk)
        servo_pwm <= (period_cnt < pulse_cyc);

endmodule

`default_nettype wire