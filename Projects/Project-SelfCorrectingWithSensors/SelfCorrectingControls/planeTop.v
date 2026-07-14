`timescale 1ns / 1ps

module motor_switch_top (
    input  wire       clk,        // 100 MHz clock
    input  wire       SW0,        // SW0 acts like an enable/start button
    output reg        servo_pwm,  // JB4 -> Level Shifter -> Servo Input PWM
    output reg  [7:0] LD,         // Feedback LEDs
    
    // Left US-100 Sensor (Pmod JA)
    output reg        left_trig,  // JA2
    input  wire       left_echo,  // JA1
    
    // Right US-100 Sensor (Pmod JA)
    output reg        right_trig, // JA4
    input  wire       right_echo  // JA3
);

    // --- Microsecond Generator (1 us Tick) ---
    reg [6:0] us_divider = 0;
    reg       us_tick = 0;

    always @(posedge clk) begin
        if (us_divider < 7'd99) begin
            us_divider <= us_divider + 1;
            us_tick    <= 1'b0;
        end else begin
            us_divider <= 0;
            us_tick    <= 1'b1; 
        end
    end

    // --- Intuitive Timing Constants (In Microseconds) ---
    localparam TICK_20MS        = 20000;   
    localparam PULSE_LEFT       = 1000;    
    localparam PULSE_NEUTRAL    = 1475;    
    localparam PULSE_RIGHT      = 2000;    
    localparam TRIG_HIGH_CYCLES = 10;       
    localparam TRIG_PERIOD      = 60000;   
    localparam DIST_THRESHOLD   = 870;

    // --- 2-Stage Clock Domain Crossing Synchronizers ---
    reg left_echo_sync0  = 0, left_echo_sync1  = 0;
    reg right_echo_sync0 = 0, right_echo_sync1 = 0;
    
    always @(posedge clk) begin
        left_echo_sync0  <= left_echo;
        left_echo_sync1  <= left_echo_sync0; // Safe to use inside your system logic
        
        right_echo_sync0 <= right_echo;
        right_echo_sync1 <= right_echo_sync0; // Safe to use inside your system logic
    end

    // --- Ultrasonic Sensor Controller ---
    reg [15:0] trigger_counter = 0;
    
    reg [15:0] left_echo_count = 0;
    reg [15:0] left_distance_reg = 16'hFFFF; 
    reg        left_echo_last = 0;

    reg [15:0] right_echo_count = 0;
    reg [15:0] right_distance_reg = 16'hFFFF; 
    reg        right_echo_last = 0;

    // Trigger state machine and accumulator counters
    always @(posedge clk) begin
        if (!SW0) begin
            trigger_counter    <= 0;
            left_trig          <= 0;
            right_trig         <= 0;
            left_echo_last     <= 0;
            right_echo_last    <= 0;
            left_distance_reg  <= 16'hFFFF;
            right_distance_reg <= 16'hFFFF;
            left_echo_count    <= 0;
            right_echo_count   <= 0;
        end else begin
            // 1. Generate Trigger Signals synchronously (based on us ticks)
            if (us_tick) begin
                if (trigger_counter < TRIG_PERIOD - 1) begin
                    trigger_counter <= trigger_counter + 1;
                end else begin
                    trigger_counter <= 0;
                end

                if (trigger_counter < TRIG_HIGH_CYCLES) begin
                    left_trig  <= 1'b1;
                    right_trig <= 1'b1;
                end else begin
                    left_trig  <= 1'b0;
                    right_trig <= 1'b0;
                end
            end

            // 2. Measure Left Sensor Echo Width (Edge tracking at 100MHz, accumulation on us_tick)
            left_echo_last <= left_echo_sync1;
            if (left_echo_sync1) begin
                if (us_tick) left_echo_count <= left_echo_count + 1;
            end else if (left_echo_last && !left_echo_sync1) begin
                left_distance_reg <= left_echo_count;
                left_echo_count   <= 0;
            end

            // 3. Measure Right Sensor Echo Width (Edge tracking at 100MHz, accumulation on us_tick)
            right_echo_last <= right_echo_sync1;
            if (right_echo_sync1) begin
                if (us_tick) right_echo_count <= right_echo_count + 1;
            end else if (right_echo_last && !right_echo_sync1) begin
                right_distance_reg <= right_echo_count;
                right_echo_count   <= 0;
            end
        end
    end

    // --- Decision FSM ---
    // States: NEUTRAL when no sensor or both sensors detect something close,
    //         LEFT    when only the left  sensor is close,
    //         RIGHT   when only the right sensor is close.
    localparam STATE_NEUTRAL = 2'b00;
    localparam STATE_LEFT    = 2'b01;
    localparam STATE_RIGHT   = 2'b10;

    reg [1:0]  state = STATE_NEUTRAL;
    reg [1:0]  next_state;

    reg [14:0] target_pulse_width = PULSE_NEUTRAL;
    reg [14:0] clk_counter = 0;

    wire left_close  = (left_distance_reg < DIST_THRESHOLD);
    wire right_close = (right_distance_reg < DIST_THRESHOLD);

    // Next-state logic (combinational)
    always @(*) begin
        case (state)
            STATE_LEFT:  next_state = (left_close && !right_close) ? STATE_LEFT  : STATE_NEUTRAL;
            STATE_RIGHT: next_state = (right_close && !left_close) ? STATE_RIGHT : STATE_NEUTRAL;
            default:     begin // STATE_NEUTRAL
                if (left_close && !right_close)
                    next_state = STATE_LEFT;
                else if (right_close && !left_close)
                    next_state = STATE_RIGHT;
                else
                    next_state = STATE_NEUTRAL; // covers: neither detected, or both detected
            end
        endcase
    end

    // State register
    always @(posedge clk) begin
        if (!SW0)
            state <= STATE_NEUTRAL;
        else
            state <= next_state;
    end

    // Output logic (registered, driven by current state)
    always @(posedge clk) begin
        if (!SW0) begin
            target_pulse_width <= PULSE_NEUTRAL;
            LD                 <= 8'b0011_1100;
        end else begin
            case (state)
                STATE_LEFT: begin
                    target_pulse_width <= PULSE_LEFT;
                    LD                 <= 8'b1111_0000;
                end
                STATE_RIGHT: begin
                    target_pulse_width <= PULSE_RIGHT;
                    LD                 <= 8'b0000_1111;
                end
                default: begin // STATE_NEUTRAL
                    target_pulse_width <= PULSE_NEUTRAL;
                    LD                 <= (left_close && right_close) ? 8'b1111_1111 : 8'b0011_1100;
                end
            endcase
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