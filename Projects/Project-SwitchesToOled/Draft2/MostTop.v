//////////////////////////////////////////////////////////////////////////////////
// Company: NASA Langley
// Engineer: Christina Guo (NASA OSTEM Intern)
// 
// Create Date: 06/30/2026
// Module Name: top
// Project Name: OLED Demo
// Description: creates OLED Demo, handles user inputs to operate OLED control module
// 
// Dependencies: OLEDCtrl.v, debouncer.v, mkOledTop.v
// 
// Revision 0.01 - File Created
//
//////////////////////////////////////////////////////////////////////////////////

// >>> EDIT: added sw[7:0] and btnL to the port list.
//           sw[7:0] feeds mkOledTop with live switch values.
//           btnL triggers a re-write + update of the OLED strings.
module top(
    input        clk,
    input        btnR,   // CPU Reset - turns display on/off
    input        btnC,   // Center DPad - toggles every pixel on/off
    input        btnD,   // Bottom DPad - update display WITH clear
    input        btnU,   // Upper DPad  - update display WITHOUT clear

// ==================== EDIT: ADD SW[7:0] FOR LIVE SWITCH UPDATES & BTNL TO UPDATE STRINGS ====================
    input        btnL,   // Left DPad   - refresh strings from current switches   
    input  [7:0] sw,     // 8 slide switches fed to mkOledTop       
// ==== END OF EDIT ====    

    output       oled_sdin,
    output       oled_sclk,
    output       oled_dc,
    output       oled_res,
    output       oled_vbat,
    output       oled_vdd,
//    output oled_cs,// used in Pmod OLED implementation
    output [7:0] led
);
    //state machine codes
    localparam Idle        = 0;
    localparam Init        = 1;
    localparam Active      = 2;
    localparam Done        = 3;
    localparam FullDisp    = 4;
    localparam Write       = 5;
    localparam WriteWait   = 6;
    localparam UpdateWait  = 7;

    // ================== EDIT: CHANGED THE DISPLAY TEXT ==================
    localparam str1=" Binary :       ", str1len=16;
    localparam str3=" Base Ten :     ", str3len=16;
    // localparam str2=" Zedboard OLED  ", str2len=16;
    // localparam str4="                ", str4len=16;

    localparam AUTO_START = 1; // determines whether the OLED will be automatically initialized when the board is programmed

    //state machine registers.
    reg [2:0] state = (AUTO_START == 1) ? Init : Idle;
    reg [5:0] count = 0;//loop index variable
    reg       once = 0;//bool to see if we have set up local pixel memory in this session
        
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
    // ================= EDIT: ADDED DEBOUNCED BTNL =================
    wire dBtnL;  // btnL debounced  <<<EDIT>>>


    // ================= EDIT: ADDED OLEDTOP INSTANTIATION =================
    wire [63:0] oled_binary_row;   // live output from mkOledTop
    wire [63:0] oled_decimal_row;  // live output from mkOledTop
    wire        rdy_bin, rdy_dec, rdy_sw; // all hardwired 1'b1 inside mkOledTop

    mkOledTop u_mkOledTop (
        .CLK              (clk),
        .RST_N            (~rst),           // active-low reset, use debounced rst
        .get_binary_row   (oled_binary_row),
        .RDY_get_binary_row (rdy_bin),
        .get_decimal_row  (oled_decimal_row),
        .RDY_get_decimal_row (rdy_dec),
        .put_switches_1   (sw),
        .EN_put_switches  (1'b1),           // always enabled; module updates every cycle
        .RDY_put_switches (rdy_sw)
    );

    // snapshot registers, added to allow changes in the binary and base ten strings within the state machine
    reg [63:0] get_new_binary_row  = 64'h2020202020202020;  // spaces until first latch
    reg [63:0] get_new_decimal_row = 64'h2020202020202020;




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
        .DC                 (oled_dc),
        .RES                (oled_res),
        .VBAT               (oled_vbat),
        .VDD                (oled_vdd)
    );
//    assign oled_cs = 1'b0;


// ONLY "WRITES" THE STORED STRINGS ONCE, DOES NOT UPDATE CONTINUOUSLY LIKE HOW I WANT
// ESSENTIALLY JUST INDEXES THROUGH THE STRING AND MAKES IT ASCII 
//    always@(write_base_addr)
//        case (write_base_addr[8:7])//select string as [y]
//        0: write_ascii_data <= 8'hff & (str1 >> ({3'b0, (str1len - 1 - write_base_addr[6:3])} << 3));//index string parameters as str[x]
//        1: write_ascii_data <= 8'hff & (str2 >> ({3'b0, (str2len - 1 - write_base_addr[6:3])} << 3));
//        2: write_ascii_data <= 8'hff & (str3 >> ({3'b0, (str3len - 1 - write_base_addr[6:3])} << 3));
//        3: write_ascii_data <= 8'hff & (str4 >> ({3'b0, (str4len - 1 - write_base_addr[6:3])} << 3));
//        endcase

    // EDIT:    og code used static always, couldn't update the live switches 
    //          this new code (hopefully) iterates through the string properly wire [3:0] col  = write_base_addr[6:3];  // character column 0-15
    wire [1:0] row  = write_base_addr[8:7];  // display row 0-3
    wire       col_in_snap = (col <= 4'd7);   // cols 0-7 come from snapshot
  wire [3:0] col  = write_base_addr[6:3];       // character column 0-15
    wire [1:0] row  = write_base_addr[8:7];       // display row 0-3
    // write_base_addr[6] is the MSB of the 4-bit column index.
    // When 0: column is 0-7  (within the 8-char snapshot).
    // When 1: column is 8-15 (beyond the snapshot -> pad with space).
    wire       col_in_snap = ~write_base_addr[6]; // <<<EDIT: was (col <= 4'd7)>>>
    // select the correct 8-bit char from a 64-bit snapshot vector
    // col is 0-7; bit slice = [63-col*8 -: 8]
    function [7:0] char_from_row;
        input [63:0] vec;
        input [3:0]  c;
        begin
            case (c)
                4'd0: char_from_row = vec[63:56];
                4'd1: char_from_row = vec[55:48];
                4'd2: char_from_row = vec[47:40];
                4'd3: char_from_row = vec[39:32];
                4'd4: char_from_row = vec[31:24];
                4'd5: char_from_row = vec[23:16];
                4'd6: char_from_row = vec[15:8];
                4'd7: char_from_row = vec[7:0];
                default: char_from_row = 8'h20; // space
            endcase
        end
    endfunction

    always @(*) begin
        case (row)
            2'b00: // Row 0 -> binary string
                write_ascii_data = col_in_snap ? char_from_row(get_new_binary_row,  col) : 8'h20;
            2'b01: // Row 1 -> decimal string
                write_ascii_data = col_in_snap ? char_from_row(get_new_decimal_row, col) : 8'h20;
            default: // Rows 2-3 -> blank
                write_ascii_data = 8'h20;
        endcase
    end

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
    // ============================ EDIT: DEBOUNCER FOR BTNL (REFRESH) ============================
    debouncer #(
        .COUNT_MAX(65535), 
        .COUNT_WIDTH(16)
    ) get_dBtnL (
        .clk(clk), 
        .A(btnL), 
        .B(dBtnL)
    );

    assign led = update_ready;       //display whether btnU, BtnD controls are available..
    assign init_done = disp_off_ready | toggle_disp_ready | write_ready | update_ready;//parse ready signals for clarity
    assign init_ready = disp_on_ready;
    
    always @(posedge clk) begin
    
    // EDIT:    added code to get the updated data after the first write cycle after INIT
    //          OR when the btnL is pressed while the OLED is still Active and it is write_ready
    //          updates the strings to the "live" switches before sending it to the write loop, while keeping the states stable
        if ((state == Active && once == 0 && write_ready) ||
            (state == Active && dBtnL && write_ready)) begin
            get_new_binary_row  <= oled_binary_row;
            get_new_decimal_row <= oled_decimal_row;
        end
    // END OF EDITS

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
            Active: begin
                if (rst && disp_off_ready) begin
                    disp_off_start <= 1'b1;
                    state <= Done;
                end else if (once == 0 && write_ready) begin
                    write_start    <= 1'b1;
                    write_base_addr <= 'b0;    //IF ERRORS ADD 9 BACK
                    state <= WriteWait;

                // EDIT:    added logic for when btnL is pressed --> updates and re-writes all the chars
                end else if (once == 1 && dBtnL && write_ready) begin
                    write_start    <= 1'b1;
                    write_base_addr <= 9'b0;
                    once <= 0;          // re-use the write loop; once will be set to 1 again at its end
                    state <= WriteWait;

                end else if (once == 1 && dBtnU == 1) begin
                    update_start <= 1'b1;
                    update_clear <= 1'b0;
                    state <= UpdateWait;
                end else if (once == 1 && dBtnD == 1) begin
                    update_start <= 1'b1;
                    update_clear <= 1'b1;
                    state <= UpdateWait;
                end else if (dBtnC == 1'b1 && toggle_disp_ready == 1'b1) begin
                    toggle_disp_start <= 1'b1;
                    state <= FullDisp;
                end
            end
            Write: begin
                write_start     <= 1'b1;
                write_base_addr <= write_base_addr + 9'h8;
                //write_ascii_data updated with write_base_addr
                state <= WriteWait;
            end
            WriteWait: begin
                write_start <= 1'b0;
                if (write_ready == 1'b1) begin
                    if (write_base_addr == 9'h1f8) begin
                        once  <= 1;
                
                // EDIT:    after write, updates the new strings automatically
                        update_start <= 1'b1;
                        update_clear <= 1'b0;
                        state <= UpdateWait;
                // END OF EDITS

                    end else begin
                        state <= Write;
                    end
                end
            end
            UpdateWait: begin
                update_start <= 1'b0;
                // EDIT:    changed exit logic 
                if (init_done && !dBtnU && !dBtnD && !dBtnL)
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
    end
endmodule