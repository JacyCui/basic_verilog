//------------------------------------------------------------------------------
// fifo_single_clock_reg_v2.sv
// published as part of https://github.com/pConst/basic_verilog
// Konstantin Pavlov, pavlovconst@gmail.com
//------------------------------------------------------------------------------

// INFO ------------------------------------------------------------------------
//  Single-clock FIFO buffer implementation, also known as "queue"
//
//  I`ve made two variants of fifo_single_clock_reg module - v1 and v2
//  Both variants are valid, both operate identically from an outside observer`s
//    view. Only internal r/w pointers operation is different.
//
//  Features:
//  - single clock operation
//  - configurable depth and data width
//  - one write- and one read- port in "FWFT" or "normal" mode
//  - protected against overflow and underflow
//  - simultaneous read and write operations supported BUT:
//        only read will happen if simultaneous rw from full fifo
//        only write will happen if simultaneous rw from empty fifo
//        Always honor empty and full flags!
//  - (new!) optional fifo contents initialization
//
//  See also "lifo.sv" module for similar LIFO buffer implementation


/* --- INSTANTIATION TEMPLATE BEGIN ---

fifo_single_clock_reg_v2 #(
  .FWFT_MODE( "TRUE" ),
  .DEPTH( 8 ),
  .DATA_W( 32 ),

  // optional initialization
  .INIT_FILE( "fifo_single_clock_reg_v2_init.svh" ),
  .INIT_CNT( 10 )
) FF1 (
  .clk( clk ),
  .nrst( 1'b1 ),

  .w_req(  ),
  .w_data(  ),

  .r_req(  ),
  .r_data(  ),

  .cnt(  ),
  .empty(  ),
  .full(  )
);

--- INSTANTIATION TEMPLATE END ---*/

module fifo_single_clock_reg_v2 #( parameter

  FWFT_MODE = "TRUE",             // "TRUE"  - first word fall-trrough" mode
                                  // "FALSE" - normal fifo mode
  DEPTH = 32,                      // max elements count == DEPTH, DEPTH MUST be power of 2
  DEPTH_W = clogb2(DEPTH)+1,      // elements counter width, extra bit to store
                                  // "fifo full" state, see cnt[] variable comments

  DATA_W = 32,                    // data field width

  // optional initialization
  USE_INIT_FILE = "FALSE",        // "TRUE"  - uses special filethat provides init data
                                  // "FALSE" - initializes with '0
  INIT_CNT = '0                   // sets desired initial cnt[]
)(
  input clk,
  input nrst,                     // inverted reset

  // input port
  input w_req,
  input [DATA_W-1:0] w_data,

  // output port
  input r_req,
  output logic [DATA_W-1:0] r_data,

  // helper ports
  output logic [DEPTH_W-1:0] cnt,
  output logic empty,
  output logic full,

  output logic fail
);

  // fifo data
  logic [DEPTH-1:0][DATA_W-1:0] data;

  // read and write pointers
  logic [DEPTH_W-1:0] w_ptr;
  logic [DEPTH_W-1:0] r_ptr;

  // fofo initialization
  // Modelsim gives suppressable error here
  // "(vlog-7061) Variable 'data' driven in an always_ff block, may not be driven by any other process"
/*  generate
    initial begin
      if( USE_INIT_FILE ) begin
        `include "fifo_single_clock_reg_v2_init.svh"
        w_ptr[DEPTH_W-1:0] <= INIT_CNT[DEPTH_W-1:0];
        r_ptr[DEPTH_W-1:0] <= '0;
        cnt[DEPTH_W-1:0] <= INIT_CNT[DEPTH_W-1:0];
      end else begin
        data <= '0;
        w_ptr[DEPTH_W-1:0] <= '0;
        r_ptr[DEPTH_W-1:0] <= '0;
        cnt[DEPTH_W-1:0] <= '0;
      end
    end // initial
  endgenerate */


  // data output buffer for normal fifo mode
  logic [DATA_W-1:0] data_buf = '0;

  always_ff @(posedge clk) begin
    integer i;
    if ( ~nrst ) begin
      if( USE_INIT_FILE ) begin
        `include "fifo_single_clock_reg_v2_init.svh"
        w_ptr[DEPTH_W-1:0] <= INIT_CNT[DEPTH_W-1:0];
        r_ptr[DEPTH_W-1:0] <= '0;
        cnt[DEPTH_W-1:0] <= INIT_CNT[DEPTH_W-1:0];
      end else begin
        data <= '0;
        w_ptr[DEPTH_W-1:0] <= '0;
        r_ptr[DEPTH_W-1:0] <= '0;
        cnt[DEPTH_W-1:0] <= '0;
      end
      data_buf[DATA_W-1:0] <= '0;
    end else begin
      unique case ({w_req, r_req})
        2'b00: ; // nothing

        2'b01: begin  // reading out
          if( ~empty ) begin
            r_ptr[DEPTH_W-1:0] <= inc_ptr(r_ptr[DEPTH_W-1:0]);
            cnt[DEPTH_W-1:0] <= cnt[DEPTH_W-1:0] - 1'b1;
            data_buf[DATA_W-1:0] <= data[r_ptr[DEPTH_W-1:0]];
          end
        end

        2'b10: begin  // writing in
          if( ~full ) begin
            w_ptr[DEPTH_W-1:0] <= inc_ptr(w_ptr[DEPTH_W-1:0]);
            data[w_ptr[DEPTH_W-1:0]] <= w_data[DATA_W-1:0];
            cnt[DEPTH_W-1:0] <= cnt[DEPTH_W-1:0] + 1'b1;
          end
        end

        2'b11: begin  // simultaneously reading and writing
          if( empty ) begin
            w_ptr[DEPTH_W-1:0] <= inc_ptr(w_ptr[DEPTH_W-1:0]);
            data[w_ptr[DEPTH_W-1:0]] <= w_data[DATA_W-1:0];
            cnt[DEPTH_W-1:0] <= cnt[DEPTH_W-1:0] + 1'b1;
          end else if( full ) begin
            r_ptr[DEPTH_W-1:0] <= inc_ptr(r_ptr[DEPTH_W-1:0]);
            cnt[DEPTH_W-1:0] <= cnt[DEPTH_W-1:0] - 1'b1;

            data_buf[DATA_W-1:0] <= data[r_ptr[DEPTH_W-1:0]];
          end else begin
            w_ptr[DEPTH_W-1:0] <= inc_ptr(w_ptr[DEPTH_W-1:0]);
            data[w_ptr[DEPTH_W-1:0]] <= w_data[DATA_W-1:0];
            //cnt[DEPTH_W-1:0] <=  // data counter does not change here

            r_ptr[DEPTH_W-1:0] <= inc_ptr(r_ptr[DEPTH_W-1:0]);
            //cnt[DEPTH_W-1:0] <=  // data counter does not change here
            data_buf[DATA_W-1:0] <= data[r_ptr[DEPTH_W-1:0]];
          end
        end
      endcase
    end
  end

  always_comb begin
    empty = ( cnt[DEPTH_W-1:0] == '0 );
    full = ( cnt[DEPTH_W-1:0] == DEPTH );

    if( FWFT_MODE == "TRUE" ) begin    // first-word fall-through mode
      if( ~empty ) begin
        r_data[DATA_W-1:0] = data[r_ptr[DEPTH_W-1:0]];
      end else begin
        r_data[DATA_W-1:0] = '0;
      end
    end else begin    // normal mode
      r_data[DATA_W-1:0] = data_buf[DATA_W-1:0];
    end

    fail = ( empty && r_req ) ||
           ( full && w_req );
  end


  function [DEPTH_W-1:0] inc_ptr (
    input [DEPTH_W-1:0] ptr
  );
    if( ptr[DEPTH_W-1:0] == DEPTH-1 ) begin
      inc_ptr[DEPTH_W-1:0] = '0;
    end else begin
      inc_ptr[DEPTH_W-1:0] = ptr[DEPTH_W-1:0] + 1'b1;
    end
  endfunction

  `include "clogb2.svh"

endmodule
