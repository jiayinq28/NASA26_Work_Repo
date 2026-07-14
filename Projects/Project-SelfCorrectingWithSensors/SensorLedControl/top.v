`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: NASA Langley OSTEM
// Engineer: Christina Guo
// Create Date: 07/10/2026
// Design Name: Sensor Integration Project
// Module Name: us100_led_control
// Description: Fixed array pin mismatches and configured JA4 for trigger 
//              and JA3 for echo.
//////////////////////////////////////////////////////////////////////////////////

module us100_led_control(
    input  wire       clk,                  // 100 MHz oscillator (GCLK pin)
    input  wire       get_sensor1_echo,     // Mapped to JA3 (Y10)
    output reg        get_sensor1_trigger,  // Mapped to JA4 (AA9)
    output wire [7:0] LD,                   // Vector representation matching XDC syntax
    
    // Unused JA lines declared as scalars to avoid synthesis mismatches
    output wire       JA1,
    output wire       JA2,
    output wire       JA7,
    output wire       JA8,
    output wire       JA9,
    output wire       JA10
);

    // Keep unused Pins safe via high-impedance
    assign {JA1, JA2, JA7, JA8, JA9, JA10} = 6'bzzzzzz;

    // Registers for sensor calculations
    reg [23:0] refresh_counter = 0; 
    reg [9:0]  trig_counter    = 0; 
    reg [23:0] echo_counter    = 0; 
    reg [15:0] distance_cm     = 0; 
    reg [7:0]  led_reg         = 8'b0000_0000;

    // State definitions
    localparam IDLE             = 3'b000,
               TRIG_ON          = 3'b001,
               WAIT_ECHO_HIGH   = 3'b010,
               MEASURE_ECHO     = 3'b011,
               CALCULATE        = 3'b100;
               
    reg [2:0] state = IDLE;

    // Continuous assignment mapping the register to the output port wire vector
    assign LD = led_reg;

    // FSM Logic Loop
    always @(posedge clk) begin
        case (state)
            IDLE: begin
                get_sensor1_trigger <= 1'b0;
                if (refresh_counter < 24'd6_000_000) begin
                    refresh_counter <= refresh_counter + 1;
                end else begin
                    refresh_counter <= 0;
                    state           <= TRIG_ON;
                end
            end

            TRIG_ON: begin
                get_sensor1_trigger <= 1'b1;
                if (trig_counter < 10'd1000) begin
                    trig_counter <= trig_counter + 1;
                end else begin
                    trig_counter        <= 0;
                    get_sensor1_trigger <= 1'b0;
                    state               <= WAIT_ECHO_HIGH;
                end
            end

            WAIT_ECHO_HIGH: begin
                if (get_sensor1_echo == 1'b1) begin
                    echo_counter <= 0;
                    state        <= MEASURE_ECHO;
                end
            end

            MEASURE_ECHO: begin
                if (get_sensor1_echo == 1'b1) begin
                    echo_counter <= echo_counter + 1;
                end else begin
                    state        <= CALCULATE;
                end
            end

            CALCULATE: begin
                distance_cm <= echo_counter / 5882;
                state       <= IDLE;
            end

            default: state <= IDLE;
        endcase
    end

    // Zone comparator logic blocks
    always @(posedge clk) begin
        if (distance_cm == 0 || distance_cm > 200) begin
            led_reg <= 8'b0000_0000;
        end 
        else if (distance_cm <= 10) begin
            led_reg <= 8'b1111_1111; 
        end 
        else if (distance_cm <= 25) begin
            led_reg <= 8'b0001_1111; 
        end 
        else if (distance_cm <= 50) begin
            led_reg <= 8'b0000_0111; 
        end 
        else if (distance_cm <= 100) begin
            led_reg <= 8'b0000_0001; 
        end 
        else begin
            led_reg <= 8'b0000_0000;
        end
    end

endmodule