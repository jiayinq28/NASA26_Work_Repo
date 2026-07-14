`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Digilent Inc.
// Engineer: Arthur Brown
// 
// Create Date: 10/1/2016
// Module Name: top
// Project Name: OLED Demo
// Tool Versions: Vivado 2016.4
// Description: creates OLED Demo, handles user inputs to operate OLED control module
// 
// Dependencies: OLEDCtrl.v, debouncer.v
// 
// Revision 0.01 - File Created
//
//////////////////////////////////////////////////////////////////////////////////

module top(
    input clk,
    input btnR,// CPU Reset Button turns the display on and off
    input btnC,// Center DPad Button turns every pixel on the display on or resets to previous state
    input btnD,// Upper DPad Button updates the delay to the contents of the local memory
    input btnU,// Bottom DPad Button clears the display
    input [7:0] sw,// EDIT: added switch input port, read by the Bluespec-generated mkOledTop module
    output oled_sdin,
    output oled_sclk,
    output oled_dc,
    output oled_res,
    output oled_vbat,
    output oled_vdd,
//    output oled_cs,// used in Pmod OLED implementation
    output [7:0] led
);
    //state machine codes
    localparam Idle       = 0;
    localparam Init       = 1;
    localparam Active     = 2;
    localparam Done       = 3;
    localparam FullDisp   = 4;
    localparam Write      = 5;
    localparam WriteWait  = 6;
    localparam UpdateWait = 7;
    
    //text to be displayed
    localparam str1=" I am the       ", str1len=16;
    localparam str2=" Zedboard OLED  ", str2len=16;
    // EDIT (revised): str3/str4 now read from SNAPSHOT registers, not the live
    // mkOledTop wires directly. Previously str3/str4 were combinational wires
    // tied straight to oledTop_binary_row/oledTop_decimal_row, which are
    // continuously driven by mkOledTop based on `sw`. The Write/WriteWait walk
    // takes ~32 clock cycles to sample all 4 rows into local memory; if `sw`
    // changed mid-walk, different characters of the same row could get sampled
    // from different switch values (a torn read). The fix is to latch the
    // switch-derived bytes into registers ONCE, at the moment a refresh is
    // triggered (see Active state below), BEFORE the FSM starts walking
    // states -- so the entire walk reads a stable, frozen snapshot.
    reg [127:0] str3;
    localparam str3len = 16;
    reg [127:0] str4;
    localparam str4len = 16;
    
    localparam AUTO_START = 1; // determines whether the OLED will be automatically initialized when the board is programmed
    	
    //state machine registers.
    reg [2:0] state = (AUTO_START == 1) ? Init : Idle;
    reg [5:0] count = 0;//loop index variable
    reg       once = 0;//bool to see if we have set up local pixel memory in this session
    reg       refresh_clear = 0;// EDIT: new register; remembers update_clear value across the re-sample Write pass, for button-triggered refreshes
        
    //oled control signals
    //command start signals, assert high to start command
    reg        update_start = 0;        //update oled display over spi
    reg        disp_on_start = AUTO_START;       //turn the oled display on
    reg        disp_off_start = 0;      //turn the oled display off
    reg        toggle_disp_start = 0;   //turns on every pixel on the oled, or returns the display to before each pixel was turned on
    reg        write_start = 0;         //writes a character bitmap into local memory
    //data signals for oled controls
    reg        update_clear = 0;        //when asserted high, an update command clears the display, instead of filling from memory
    reg  [8:0] write_base_addr = 0;     //location to write character to, two most significant bits are row position, 0 is topmost. bottom seven bits are X position, addressed by pixel x position.
    reg  [7:0] write_ascii_data = 0;    //ascii value of character to write to memory
    //active high command ready signals, appropriate start commands are ignored when these are not asserted high
    wire       disp_on_ready;
    wire       disp_off_ready;
    wire       toggle_disp_ready;
    wire       update_ready;
    wire       write_ready;
    
    //debounced button signals used for state transitions
    wire       rst;     // CPU RESET BUTTON turns the display on and off, on display_on, local memory is filled from string parameters
    wire       dBtnC;   // Center DPad Button tied to toggle_disp command 
    wire       dBtnU;   // Upper DPad Button tied to update without clear
    wire       dBtnD;   // Bottom DPad Button tied to update with clear
    	
	//instantiate OLED controller
    OLEDCtrl m_OLEDCtrl (
        .clk                (clk),              
        .write_start        (write_start),      
        .write_ascii_data   (write_ascii_data), 
        .write_base_addr    (write_base_addr),  
        .write_ready        (write_ready),      
        .update_start       (update_start),     
        .update_ready       (update_ready),     
        .update_clear       (update_clear),    
        .disp_on_start      (disp_on_start),    
        .disp_on_ready      (disp_on_ready),    
        .disp_off_start     (disp_off_start),   
        .disp_off_ready     (disp_off_ready),   
        .toggle_disp_start  (toggle_disp_start),
        .toggle_disp_ready  (toggle_disp_ready),
        .SDIN               (oled_sdin),        
        .SCLK               (oled_sclk),        
        .DC                 (oled_dc  ),        
        .RES                (oled_res ),        
        .VBAT               (oled_vbat),        
        .VDD                (oled_vdd )
    );
//    assign oled_cs = 1'b0;

    // ===== EDIT: new block start - mkOledTop instantiation ===================
    // Bluespec-generated module: computes the switch sum, drives `led`,
    // and produces 8-char binary/decimal ASCII rows from the switch state.
    wire [63:0] oledTop_binary_row;
    wire [63:0] oledTop_decimal_row;
    wire [7:0]  oledTop_leds;
    mkOledTop m_OledTop (
        .CLK             (clk),
        .RST_N           (1'b1),// no active-low system reset in this design; tie deasserted
        .put_switches_1  (sw),
        .EN_put_switches (1'b1),
        .get_binary_row  (oledTop_binary_row),
        .get_decimal_row (oledTop_decimal_row),
        .get_leds        (oledTop_leds)
    );

    // ===== EDIT: new block end ================================================
    // NOTE: str3/str4 are no longer continuously assigned from oledTop_binary_row/
    // oledTop_decimal_row here. They are latched inside the FSM instead -- see
    // the Idle and Active states below -- so the snapshot is stable for the
    // entire duration of the Write/WriteWait walk.

    always@(write_base_addr)
        case (write_base_addr[8:7])//select string as [y]
        0: write_ascii_data <= 8'hff & (str1 >> ({3'b0, (str1len - 1 - write_base_addr[6:3])} << 3));//index string parameters as str[x]
        1: write_ascii_data <= 8'hff & (str2 >> ({3'b0, (str2len - 1 - write_base_addr[6:3])} << 3));
        2: write_ascii_data <= 8'hff & (str3 >> ({3'b0, (str3len - 1 - write_base_addr[6:3])} << 3));
        3: write_ascii_data <= 8'hff & (str4 >> ({3'b0, (str4len - 1 - write_base_addr[6:3])} << 3));
        endcase
        
    //debouncers ensure single state machine loop per button press. noisy signals cause possibility of multiple "positive edges" per press.
    debouncer #(
        .COUNT_MAX(65535),
        .COUNT_WIDTH(16)
    ) get_dBtnC (
        .clk(clk),
        .A(btnC),
        .B(dBtnC)
    );
    debouncer #(
        .COUNT_MAX(65535),
        .COUNT_WIDTH(16)
    ) get_dBtnU (
        .clk(clk),
        .A(btnU),
        .B(dBtnU)
    );
    debouncer #(
        .COUNT_MAX(65535),
        .COUNT_WIDTH(16)
    ) get_dBtnD (
        .clk(clk),
        .A(btnD),
        .B(dBtnD)
    );
    debouncer #(
        .COUNT_MAX(65535),
        .COUNT_WIDTH(16)
    )  get_rst (
        .clk(clk),
        .A(btnR),
        .B(rst)
    );
    
    assign led = {update_ready, oledTop_leds[6:0]};// EDIT: was `assign led = update_ready;` -- now led[7]=update_ready (board ready indicator), led[6:0]=switch sum (lower 7 bits); full 8-bit switch value still shown on the OLED binary row
    assign init_done = disp_off_ready | toggle_disp_ready | write_ready | update_ready;//parse ready signals for clarity
    assign init_ready = disp_on_ready;
    always@(posedge clk)
        case (state)
            Idle: begin
                if (rst == 1'b1 && init_ready == 1'b1) begin
                    disp_on_start <= 1'b1;
                    state <= Init;
                end
                once <= 0;
            end
            Init: begin
                disp_on_start <= 1'b0;
                if (rst == 1'b0 && init_done == 1'b1)
                    state <= Active;
            end
            Active: begin // hold until ready, then accept input
                if (rst && disp_off_ready) begin
                    disp_off_start <= 1'b1;
                    state <= Done;
                end else if (once == 0 && write_ready) begin
                    str3 <= {64'h2020202020202020, oledTop_binary_row};// EDIT: snapshot latched here, before walk starts
                    str4 <= {64'h2020202020202020, oledTop_decimal_row};// EDIT: snapshot latched here, before walk starts
                    write_start <= 1'b1;
                    write_base_addr <= 'b0;
                    state <= WriteWait;
                // EDIT: dBtnU/dBtnD branches changed. Originally these went straight to
                // UpdateWait (update_start<=1; update_clear<=0/1; state<=UpdateWait),
                // which just re-sent whatever was ALREADY in OLED memory over SPI --
                // str3/str4 were never re-sampled, so the displayed numbers were frozen
                // at whatever the switches were at power-on.
                // Fix: latch a fresh snapshot of the switch-derived strings right here,
                // BEFORE transitioning into WriteWait/Write (i.e. before using the states
                // that walk write_base_addr), then route through that walk to re-sample
                // the frozen snapshot into local memory, then trigger the SPI update.
                end else if (once == 1 && dBtnU == 1) begin
                    str3 <= {64'h2020202020202020, oledTop_binary_row};// EDIT: snapshot latched here, before walk starts
                    str4 <= {64'h2020202020202020, oledTop_decimal_row};// EDIT: snapshot latched here, before walk starts
                    refresh_clear <= 1'b0;
                    write_start <= 1'b1;
                    write_base_addr <= 'b0;
                    state <= WriteWait;
                end else if (once == 1 && dBtnD == 1) begin
                    str3 <= {64'h2020202020202020, oledTop_binary_row};// EDIT: snapshot latched here, before walk starts
                    str4 <= {64'h2020202020202020, oledTop_decimal_row};// EDIT: snapshot latched here, before walk starts
                    refresh_clear <= 1'b1;
                    write_start <= 1'b1;
                    write_base_addr <= 'b0;
                    state <= WriteWait;
                end else if (dBtnC == 1'b1 && toggle_disp_ready == 1'b1) begin
                    toggle_disp_start <= 1'b1;
                    state <= FullDisp;
                end
            end
            Write: begin
                write_start <= 1'b1;
                write_base_addr <= write_base_addr + 9'h8;
                //write_ascii_data updated with write_base_addr
                state <= WriteWait;
            end
            WriteWait: begin
                write_start <= 1'b0;
                if (write_ready == 1'b1)
                    if (write_base_addr == 9'h1f8) begin
                        // EDIT: this if/else is new. Originally this branch always did
                        // `once <= 1; state <= Active;` unconditionally -- there was no way
                        // to tell "first-ever fill" apart from "button-triggered refresh".
                        // Now: if `once` was already 1, we got here via a button press
                        // (see Active edit above), so finish by firing the SPI update with
                        // the remembered refresh_clear value, instead of just idling in Active.
                        if (once == 1'b0) begin
                            once <= 1;
                            state <= Active;
                        end else begin
                            update_start <= 1'b1;
                            update_clear <= refresh_clear;
                            state <= UpdateWait;
                        end
                    end else begin
                        state <= Write;
                    end
            end
            UpdateWait: begin
                update_start <= 0;
                if (dBtnU == 0 && init_done == 1'b1)
                    state <= Active;
            end
            Done: begin
                disp_off_start <= 1'b0;
                if (rst == 1'b0 && init_ready == 1'b1)
                    state <= Idle;
            end
            FullDisp: begin
                toggle_disp_start <= 1'b0;
                if (dBtnC == 1'b0 && init_done == 1'b1)
                    state <= Active;
            end
            default: state <= Idle;
        endcase
endmodule