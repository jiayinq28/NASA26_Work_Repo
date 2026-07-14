`timescale 1ns / 1ps

module motor_switch_top (
    input  wire       clk,        // Raw 100 MHz clock from GCLK pin (Y9)
    input  wire       SW0,        // Switch 0: Manual Left Command
    input  wire       SW1,        // Switch 1: Manual Right Command
    input  wire       SW2,        // Switch 2: Manual Neutral Command
    output reg        servo_pwm,  // Mapped to JB4 -> Level Shifter -> Servo PWM
    output reg  [7:0] LD          // Feedback LEDs
);

    // --- Microsecond Generator (1 us Tick) ---
    // 100 MHz Clock = 10 ns period. 100 cycles = 1 us.
    reg [6:0] us_divider = 0;
    reg       us_tick = 0;

    always @(posedge clk) begin
        if (us_divider < 7'd99) begin
            us_divider <= us_divider + 1;
            us_tick    <= 1'b0;
        end else begin
            us_divider <= 0;
            us_tick    <= 1'b1; // Pulses high for 1 clock cycle every 1 us
        end
    end

    // --- Intuitive Timing Constants (In Microseconds) ---
    localparam TICK_20MS      = 20000;   // 20 ms servo period (20000 us)
    localparam PULSE_LEFT     = 1000;    // 1000 us Left
    localparam PULSE_NEUTRAL  = 1475;    // 1475 us Neutral
    localparam PULSE_RIGHT    = 2000;    // 2000 us Right

    // --- Decision Logic and Servo Driver ---
    reg [14:0] target_pulse_width = PULSE_NEUTRAL;
    reg [14:0] clk_counter = 0;

    always @(posedge clk) begin
        if (SW0) begin
            // Manual Left State
            target_pulse_width <= PULSE_LEFT;
            LD                 <= 8'b1111_0000; // Left side LEDs ON
        end 
        else if (SW1) begin
            // Manual Right State
            target_pulse_width <= PULSE_RIGHT;
            LD                 <= 8'b0000_1111; // Right side LEDs ON
        end 
        else if (SW2) begin
            // Manual Neutral State
            target_pulse_width <= PULSE_NEUTRAL;
            LD                 <= 8'b0011_1100; // Center LEDs ON
        end 
        else begin
            // Default/Idle State (No switches active)
            target_pulse_width <= PULSE_NEUTRAL;
            LD                 <= 8'b1000_0001; // Outer LEDs standby pattern
        end
    end

    // Servo PWM Output (controlled by the microsecond tick rate)
    always @(posedge clk) begin
        if (us_tick) begin
            if (clk_counter < TICK_20MS - 1) begin
                clk_counter <= clk_counter + 1;
            end else begin
                clk_counter <= 0;
            end
        end
    end

    // Glitch-free output comparator (runs at full 100 MHz clock)
    always @(posedge clk) begin
        if (clk_counter < target_pulse_width) begin
            servo_pwm <= 1'b1;
        end else begin
            servo_pwm <= 1'b0;
        end
    end

endmodule