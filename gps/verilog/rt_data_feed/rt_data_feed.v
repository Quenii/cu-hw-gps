`define DEBUG
`include "../components/debug.vh"

module rt_data_feed(
    input              clk_50,
    input              reset,
    //DM9000A Ethernet controller interface.
    output wire        enet_clk,
    input              enet_int,
    output wire        enet_rst_n,
    output wire        enet_cs_n,
    output wire        enet_cmd,
    output wire        enet_wr_n,
    output wire        enet_rd_n,
    inout wire [15:0]  enet_data,
    //Sample interface.
    input              clk_sample,
    output reg [2:0]   sample_data,      
    //Debug signals.
    output wire        link_status,
    output wire        have_data,
    output wire [8:0]  rx_fifo_available,
    output wire [8:0]  words_available,
    output wire [8:0]  packet_count,
    output wire [15:0] data_out,
    //Crap
    output wire [17:0] samp_buffer,
    output wire [2:0]  samp_count,
    input              halt,
    input              halt_packet,
    output wire [15:0] rxp_h,
    output wire [15:0] rxp_l);

   /////////////////////////
   // Ethernet Controller
   /////////////////////////

   //DM9000A Ethernet controller module.
   wire        rx_fifo_rd_req;
   wire [15:0] rx_fifo_rd_data;
   wire        rx_fifo_empty;
   //wire [8:0]  rx_fifo_available;
   dm9000a_controller dm9000a(.clk(clk_50),
                              .reset(reset),
                              .enet_clk(enet_clk),
                              .enet_int(enet_int),
                              .enet_rst_n(enet_rst_n),
                              .enet_cs_n(enet_cs_n),
                              .enet_cmd(enet_cmd),
                              .enet_wr_n(enet_wr_n),
                              .enet_rd_n(enet_rd_n),
                              .enet_data(enet_data),
                              .rx_fifo_rd_clk(enet_clk),
                              .rx_fifo_rd_req(rx_fifo_rd_req),
                              .rx_fifo_rd_data(rx_fifo_rd_data),
                              .rx_fifo_empty(rx_fifo_empty),
                              .rx_fifo_available(rx_fifo_available),
                              .halt(halt),
                              .link_status(link_status),
                              .rxp_h(rxp_h),
                              .rxp_l(rxp_l));

   ////////////////////
   // Packet Processor
   ////////////////////

   `KEEP wire        packet_empty;
   `KEEP wire        packet_read;
   `KEEP wire [15:0] packet_data;
   rtdf_packet_processor processor(.reset(reset),
                                   .clk_rx(enet_clk),
                                   .rx_fifo_rd_data(rx_fifo_rd_data),
                                   .rx_fifo_empty(rx_fifo_empty || halt_packet),
                                   .rx_fifo_rd_req(rx_fifo_rd_req),
                                   .clk_read(clk_sample),
                                   .empty(packet_empty),
                                   .read_next(packet_read),
                                   .data(packet_data),
                                   .words_available(words_available),
                                   .packet_count(packet_count));
   
   assign have_data = !packet_empty;
   assign data_out = packet_data;
   
   //When there are less than two samples in the
   //buffer (there are at least 16b available for
   //a FIFO read), read a word from the FIFO.
   `PRESERVE reg [2:0]  sample_count;
   assign packet_read = !packet_empty && sample_count<3'd2;

   ////////////////////
   // Sample Generator
   ////////////////////

   `PRESERVE reg [17:0] sample_buffer;
   `PRESERVE reg [1:0]  sample_extra;
   always @(posedge clk_sample) begin
      //Words contain 5 whole 3b samples, and one extra
      //bit. Increment the sample count by 6 if there
      //are already 2 extra bits available, and by
      //5 otherwise.
      sample_count <= reset ? 3'd0 :
                      sample_count>3'd1 ? sample_count-3'd1 :
                      packet_empty ? (sample_count==3'd1 :
                                      3'd0 :
                                      sample_count) :
                      sample_extra==2'd2 ? 3'd6 :
                      3'd5;
      
      //Each word has one extra bit. Increment count
      //by one until a whole sample (3b) is built.
      sample_extra <= reset ? 2'd0 :
                      !packet_read ? sample_extra :
                      sample_extra==2'd2 ? 2'd0 :
                      sample_extra+2'd1;

      //Shift the buffer left by one sample each cycle,
      //and append a data word when appropriate.
      sample_buffer <= reset ? 18'h0 :
                       sample_count>3'd1 ? {2'h0,sample_buffer[16:3]} :
                       packet_empty ? (sample_count==3'd1 ?
                                       {2'h0,sample_buffer[16:3]} :
                                       sample_buffer) :
                       sample_extra==2'd0 ? {2'h0,packet_data} :
                       sample_count==3'd1 ? (sample_extra==2'd1 ?
                                             {1'h0,packet_data,sample_buffer[3]} :
                                             {packet_data,sample_buffer[4:3]}) :
                       (sample_extra==2'd1 ?
                        {1'h0,packet_data,sample_buffer[0]} :
                        {packet_data,sample_buffer[1:0]});

      //Sample data is the lowest 3 bits in the buffer.
      sample_data <= sample_buffer[2:0];
   end // always @ (negedge clk_sample)

   //FIXME Remove these.
   assign samp_buffer = sample_buffer;
   assign samp_count = sample_count;
   
endmodule