// Code your design here

//==============================TOP module=======================
module dma_top #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32,
  parameter MEM_DEPTH  = 32
)(
  input rst,
  input clk,
  //CPU  <--->DMA
/*  CPU
 │
 ▼
dma_top.read_en
 │
 │ connection
 ▼
dma_reg.read_en */
  input logic read_en,
  input logic write_en,
  input logic [ADDR_WIDTH-1:0]reg_addr,
  input logic [DATA_WIDTH-1:0]reg_wdata,
  output logic [DATA_WIDTH-1:0]reg_rdata,
  
   //DMA interrupt 
  output logic irq
);
  
  //DMA reg  <---> DMA core
  logic [ADDR_WIDTH-1:0]src_addr;
  logic [ADDR_WIDTH-1:0]dst_addr;
  logic [DATA_WIDTH-1:0]length;
   logic start;
  
  //DMA core ---> DMA reg
  logic busy;
  logic done;
  logic error;
  logic irq_transfer_done;
  
  //FSM --->datapath
  logic read_en_dp;
  logic write_en_dp;
  logic capture_read_data;
  logic update_addr;
  logic update_count;
  
  //datapath ---> FSM
  logic remaining_zero;
  logic read_data_valid;
  logic write_done;
  
  //datapath <--->memory
  logic memory_read_en;
  logic [ADDR_WIDTH-1:0] memory_read_addr;
  
  logic memory_write_en;
  logic [ADDR_WIDTH-1:0] memory_write_addr;
  logic [DATA_WIDTH-1:0]memory_write_data;
  
  //memory <---> datapath
  logic [DATA_WIDTH-1:0] mem_read_data;
  logic mem_read_data_valid;
  logic mem_write_done;
  

  
  //1. DMA REGISTER
  dma_reg #(.ADDR_WIDTH(ADDR_WIDTH),
            .DATA_WIDTH(DATA_WIDTH)
           ) u_dma_reg ( 
    .clk(clk),
    .rst(rst),
    .read_en(read_en),
    .write_en(write_en),
    .reg_addr(reg_addr),
    .reg_wdata(reg_wdata),
    .reg_rdata(reg_rdata),
  
  
  //DMA configuration     dma_reg----> DMA core
    .src_addr(src_addr),
    .dst_addr(dst_addr),
    .length(length),
    .start(start),

  
  //DMA status     DMA core ---------->dma_reg
    .busy(busy),
    .done(done),
    .error(error),
  
  //DMA interrupt
    .irq_transfer_done(irq_transfer_done)
  );
  
  //2.DMA FSM
    dma_fsm u_dma_fsm (

    .clk(clk),
    .rst(rst),

    // Start
    .start(start),

    // Feedback from datapath
    .remaining_zero(remaining_zero),
    .read_data_valid(read_data_valid),
    .write_done(write_done),

    // Control to datapath
    .read_en(read_en_dp),
    .write_en(write_en_dp),
    .capture_read_data(capture_read_data),
    .update_addr(update_addr),
    .update_count(update_count),

    // Status
    .busy(busy),
    .done(done),
    .irq_transfer_done(irq_transfer_done)
  );
 
  //3.DMA datapath
   dma_datapath #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) u_dma_datapath (

    .rst(rst),
    .clk(clk),

    // Configuration
    .src_addr(src_addr),
    .dst_addr(dst_addr),
    .length(length),
    .start(start),

    // Control from FSM
    .read_en(read_en_dp),
    .write_en(write_en_dp),
    .capture_read_data(capture_read_data),
    .update_addr(update_addr),
    .update_count(update_count),

    // Memory interface
    .memory_read_en(memory_read_en),
    .memory_read_addr(memory_read_addr),

    .memory_write_en(memory_write_en),
    .memory_write_addr(memory_write_addr),
    .memory_write_data(memory_write_data),

     // Memory response
    .mem_read_data(mem_read_data),
    .mem_read_data_valid(mem_read_data_valid),
    .mem_write_done(mem_write_done),

    // Feedback to FSM
    .remaining_zero(remaining_zero),
    .read_data_valid(read_data_valid),
    .write_done(write_done)
  );

   //4.DMA memory
  dma_memory #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .MEM_DEPTH(MEM_DEPTH)
  ) u_dma_memory (

    .clk(clk),
    .rst(rst),

    // Read request
    .memory_read_en(memory_read_en),
    .memory_read_addr(memory_read_addr),

    // Write request
    .memory_write_en(memory_write_en),
    .memory_write_addr(memory_write_addr),
    .memory_write_data(memory_write_data),

    // Read response
    .mem_read_data(mem_read_data),
    .mem_read_data_valid(mem_read_data_valid),

    // Write response
    .mem_write_done(mem_write_done)
  );


  //================================================
  // INTERRUPT
  //================================================

  assign irq = irq_transfer_done;
endmodule

//================================DMA register=====================
module dma_reg #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32
)(
  input logic rst,
  input logic clk,
  
  // CPU <--->dma_reg
  input logic read_en,
  input logic write_en,
  input logic [ADDR_WIDTH-1:0] reg_addr,
  input logic [DATA_WIDTH-1:0] reg_wdata,
  output logic [DATA_WIDTH-1:0] reg_rdata,
  
  
  //DMA configuration     dma_reg----> DMA core
  output logic [ADDR_WIDTH-1:0]src_addr,
  output logic [ADDR_WIDTH-1:0]dst_addr,
  output logic [DATA_WIDTH-1:0]length,
  output logic start,

  
  //DMA status     DMA core ---------->dma_reg
  input logic busy,
  input logic done,
  input logic error,
  
  //DMA interrupt
  input logic irq_transfer_done
);
  localparam logic [ADDR_WIDTH-1:0] ADDR_CONTROL    = 32'h0000_0000;
  localparam logic [ADDR_WIDTH-1:0] ADDR_STATUS     = 32'h0000_0004;
  localparam logic [ADDR_WIDTH-1:0] ADDR_SRC_ADDR   = 32'h0000_0008;
  localparam logic [ADDR_WIDTH-1:0] ADDR_DST_ADDR   = 32'h0000_000C;
  localparam logic [ADDR_WIDTH-1:0] ADDR_LENGTH     = 32'h0000_0010;
  localparam logic [ADDR_WIDTH-1:0] ADDR_IRQ_STATUS = 32'h0000_0014;
  localparam logic [ADDR_WIDTH-1:0] ADDR_VERSION    = 32'h0000_0018;
  
  //rgister storage
  logic [ADDR_WIDTH-1:0] src_addr_reg;
  logic [ADDR_WIDTH-1:0] dst_addr_reg;
  logic [DATA_WIDTH-1:0]length_reg;
  
  logic start_reg;
  logic irq_status_reg;
  
  //fixed version;
  localparam logic [DATA_WIDTH-1:0] version_value = 32'h0001_0000;
//write 
always_ff @(posedge clk or posedge rst)
  begin
    if(rst) begin
      src_addr_reg <= 0;
      dst_addr_reg <= 0;
      length_reg <= 0;
      start_reg <= 0;
      irq_status_reg <= 1'b0;
    end
    
    else
      begin
      start_reg <= 0;
      if(write_en)
        begin
          case(reg_addr)
           ADDR_SRC_ADDR:begin
            src_addr_reg <= reg_wdata;
           end
            ADDR_DST_ADDR:begin
              dst_addr_reg <= reg_wdata;
            end
            ADDR_LENGTH:begin
              length_reg <= reg_wdata;
            end
            ADDR_CONTROL:begin
              if(reg_wdata[0] == 1)
                begin
                  start_reg <= 1;
                end
            end
            default:
              begin
              end
          endcase
           //CPU clear
          if(reg_addr == ADDR_IRQ_STATUS && reg_wdata[0])
              begin
              	irq_status_reg <= 0;
              end
        end
      end
    if(irq_transfer_done)
              begin
                 irq_status_reg <= 1'b1;
              end
  end
assign src_addr = src_addr_reg;
assign dst_addr = dst_addr_reg;
assign length = length_reg;
assign start = start_reg;
  
  //read
  always_comb begin
    reg_rdata = 0;
    if(read_en)
      begin
        case(reg_addr)
          ADDR_SRC_ADDR:
            reg_rdata = src_addr_reg;
          ADDR_DST_ADDR:
            reg_rdata = dst_addr_reg;
          ADDR_LENGTH:
            reg_rdata = length_reg;
          ADDR_CONTROL:
            reg_rdata[0] = start_reg;
          ADDR_STATUS: begin
              reg_rdata = 0;
              reg_rdata[0] = busy;
              reg_rdata[1] = done;
              reg_rdata[2] = error;
          end
          ADDR_IRQ_STATUS:
            begin
              reg_rdata = 0;
              reg_rdata[0] = irq_status_reg;
            end
          ADDR_VERSION:
            reg_rdata = version_value;
          default:
            begin
              reg_rdata = 0;
            end
        endcase
      end
  	end
endmodule

////////////////////////////////dma_fsm/////////////////////////////////
module dma_fsm(
  input clk,
  input rst,
  
  //start from logic register
  input logic start,
  
  //feedback from dma_datapath
  input logic remaining_zero,
  input logic read_data_valid,
  input logic write_done,
  
  //Signals from fsm to datapath
  
  output logic read_en,
  output logic write_en,
  output logic capture_read_data,
  output logic update_addr,
  output logic update_count,
  
  //status
  output logic busy,
  output logic done,
  output logic irq_transfer_done
  
);
 //state declartion
  typedef enum logic [2:0] {
    IDLE,
    READ,
    WAIT_READ,
    WRITE,
    UPDATE,
    DONE
  } state_reg;
  state_reg state, next_state;
  //state register
  always_ff@(posedge clk or posedge rst)
    begin
      if(rst)
        begin
          state <= IDLE;
        end
      else
        begin
          state <= next_state;
        end
    end
  
  //next_state  logic
  always_comb
    begin
      next_state = state;
      case(state)
        IDLE:
          begin
            if(start)
              begin
                next_state = READ;
              end
          end
        READ:
          begin
            next_state =  WAIT_READ;
          end
        WAIT_READ:
         begin
           if(read_data_valid)
             begin
                next_state = WRITE;
             end
           else
             begin
               next_state =  WAIT_READ;
             end
         end
        WRITE:
              begin
                if (write_done)
                  next_state = UPDATE;
              end
        UPDATE:
          begin
            if(remaining_zero)
              begin
                next_state =  DONE;
              end
            else
              begin
                next_state = READ;
              end
          end
        DONE:
          begin
            next_state = IDLE;
          end
        default:
          begin
          	next_state = IDLE;
          end
      endcase
    end
  
  
  //output logic
  always_comb
    begin
      read_en = 1'b0;
      write_en = 1'b0;
      capture_read_data = 1'b0;
      update_addr = 1'b0;
      update_count =  1'b0;
      
      busy              = 1'b0;
      done              = 1'b0;
      irq_transfer_done = 1'b0;

      
      case(state)
        IDLE:
          begin
            busy = 1'b0;
          end
        READ:
          begin
            busy = 1'b1;
            read_en =  1'b1;
          end
        WAIT_READ:
          begin
            busy = 1'b1;
            if(read_data_valid)
              begin
                capture_read_data  =  1'b1;
              end  
          end
        WRITE:
          begin
            busy = 1'b1;
            write_en =1'b1;
          end
        UPDATE:
          begin
            busy = 1'b1;
            update_addr = 1'b1;
            update_count =  1'b1;
          end
        DONE:
          begin
            busy = 1'b0;
            done = 1'b1;
            irq_transfer_done = 1'b1;
          end
        default:
          busy = 1'b0;
      endcase
    end
endmodule

////////////////////////////dma_datapath/////////////////////////////////////
module dma_datapath #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32
)(
  input rst,
  input clk,
  
  // configuration from dma_reg
  input logic [ADDR_WIDTH-1:0]src_addr,
  input logic [ADDR_WIDTH-1:0]dst_addr,
  input logic [DATA_WIDTH-1:0]length,
  
  //start from DMA reg
  input logic start,  
  
  // configuration from FSM
  input logic read_en,
  input logic write_en,
  input logic capture_read_data,
  input logic update_addr,
  input logic update_count,
  
  //////////interface with DMA memory
  //datapath -> memory
  output logic memory_read_en,
  output logic [ADDR_WIDTH-1:0] memory_read_addr,
  
  output logic memory_write_en,
  output logic [ADDR_WIDTH-1:0] memory_write_addr,
  output logic [DATA_WIDTH-1:0]memory_write_data,
  
  //memory -> datapath
  input logic [DATA_WIDTH-1:0] mem_read_data,
  input logic mem_read_data_valid,
  input logic mem_write_done,
  
  
  //feedback from fsm
  output logic remaining_zero,
  output logic read_data_valid,
  output logic write_done

);
  logic [ADDR_WIDTH-1:0] src_addr_current;
  logic [ADDR_WIDTH-1:0] dst_addr_current;
  logic [DATA_WIDTH-1:0] remaining_count;
  logic [DATA_WIDTH-1:0] read_data_reg;

  //========DATAPATH REGISTER============
  always_ff @(posedge clk or posedge rst)
    begin
      if(rst)
        begin
          src_addr_current <= 32'b0;
          dst_addr_current <= 32'b0;
          remaining_count  <= 32'b0;
          read_data_reg    <= 32'b0;
        end
      else
        begin
          //start new dma transfer
          if(start)
            begin
              src_addr_current <= src_addr;
              dst_addr_current <= dst_addr;
              remaining_count  <= length >> 2;
            end
          
          //capture the data
          else if(capture_read_data)
            begin
              read_data_reg <= mem_read_data;
            end
          //addr update
          else if(update_addr)
            begin
              src_addr_current <= src_addr_current + 32'h4;
              dst_addr_current <= dst_addr_current + 32'h4;
            end
          
          // count update
          else if(update_count)
            begin
            	remaining_count <= remaining_count - 1'b1;  
            end
        end
    end
  //==============MEMORY read interface============
  assign memory_read_en =  read_en;
  assign memory_read_addr = src_addr_current;
  //==============MEMORY write interface===========
  assign memory_write_en = write_en;
  assign memory_write_addr = dst_addr_current;
  assign memory_write_data = read_data_reg;
  
  //=============feedback signals to FSM============
  assign read_data_valid = mem_read_data_valid;
  assign write_done = mem_write_done;
  assign remaining_zero = (remaining_count == 0);
endmodule
  
////////////////////////////DMA_memory_interface/////////////////////////

module dma_memory #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32,
  parameter MEM_DEPTH  = 1024
)(
  input clk,
  input rst,
  
  //read request from datapath
  input logic memory_read_en,
  input logic [ADDR_WIDTH-1:0] memory_read_addr,
  
  // write request from datapath
  input logic memory_write_en,
  input logic [ADDR_WIDTH-1:0] memory_write_addr,
  input logic [DATA_WIDTH-1:0]memory_write_data,
  //read response from memory
  output logic [DATA_WIDTH-1:0] mem_read_data,
  output logic mem_read_data_valid,
  //write response from memory
  output logic mem_write_done
);
  logic [DATA_WIDTH-1:0]mem[MEM_DEPTH-1:0];
  
  
  always_ff @(posedge clk or posedge rst)
    begin
      if(rst)
        begin
          mem_read_data <= 0;
          mem_read_data_valid <= 0;
          mem_write_done <= 0;
        end
      else
        begin
          // default response signals
            mem_read_data_valid <= 1'b0;
            mem_write_done      <= 1'b0;
          
          //memory read
          if(memory_read_en)
            begin
              mem_read_data <= mem[memory_read_addr >> 2];
              mem_read_data_valid <= 1'b1;
            end
          
          //memory write
          if(memory_write_en)
            begin
              mem[memory_write_addr >> 2] <= memory_write_data;
              mem_write_done <= 1'b1;
            end
        end
    end
endmodule




  
