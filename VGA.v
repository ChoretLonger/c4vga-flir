
module VGA(clk,
				r,g,b,hs,vs,//addr,db,
				sysled,
				lep_sclk,lep_scs,lep_smiso,lep_go,
				cam_vsync,cam_href,cam_pclk,cam_rst,cam_pwdn,
				sdram_clk,sdram_cke,sdram_cmd_reg,sdram_BA,sdram_add,sdram_dq
				);

input clk; //40MHz 800x600
//input db;
//output addr;
output r,g,b,hs,vs;
output sysled;

// SDRAM ports
output sdram_clk;
output sdram_cke;
output sdram_cmd_reg;
output sdram_BA;
output sdram_add;
inout [15:0] sdram_dq;

// camera ports
//output clk2cam;
output cam_rst;
output cam_pwdn;
input cam_pclk;
input cam_vsync;
input cam_href;
//input [7:0] cam_dat;

// lepton
input lep_go ;
output lep_sclk ;
output lep_scs  ;
input  lep_smiso;

//assign cam_rst = 1 ;
assign cam_pwdn = 0 ;

// 3 bit command reg values, RAS CAS WE
parameter SDRAM_NOP     = 3'b111 ,
			 SDRAM_SETMODE = 3'b000 ,
			 SDRAM_AUTOREF = 3'b001 ,
			 SDRAM_BANKACTROW = 3'b011 ,
			 SDRAM_READCOL = 3'b101 ,
			 SDRAM_WRTECOL = 3'b100 ,
			 SDRAM_PRECHAR = 3'b010 ;

// VGA display port
reg hs,vs;
reg[10:0] count_v,count_h;
reg[18:0]addr;
wire[15:0]db;
reg flag;
wire[5:0] r;
wire[5:0] g;
wire[5:0] b;
			 
// pll clock part
wire clk100m;
wire clk100m_dq;
wire dclk;

assign clk2cam = dclk ;

wire locked;
pll (
		.inclk0(clk),
		.c0(clk100m),
		.c1(clk100m_dq),
		.c2(dclk),
		.locked(locked)
	  );
	  
reg [22:0] timer ;
wire cfg_sta;
assign sysled = cfg_sta ;//? timer[22] : 1'b1 ;
always@(posedge dclk) timer <= timer + 1 ;

wire lep_go ;
wire lep_sclk ;
wire lep_scs ;
wire lep_smiso ;
wire lep_dat_pclk ;
wire lep_framestart ;
wire [15:0] lep_dat ;

reg [15:0]lep_buf[0:159];
reg [7:0] lep_buf_addr ;
wire      lep_buf_pos = lep_buf_addr[3];

reg [18:0] lep_pix_cnt ;

wire [7:0] resdat ;
wire       res_val;

lepton lepton(
					.clk            (clk),
					.lep_go_in      (locked),
					.spiclk     	 (lep_sclk),
					.spics      	 (lep_scs),
					.spimiso        (lep_smiso),
					.lep_dat_pclk   (lep_dat_pclk),
					.lep_framestart (lep_framestart),
					.lep_dat        (lep_dat),
					.result         (resdat),
					.res_val        (res_val)
);



// SDRAM control
wire sdram_clk = clk100m_dq ;
reg sdram_cke;
reg [2:0] sdram_cmd_reg;
wire RAS = sdram_cmd_reg[2];
wire CAS = sdram_cmd_reg[1];
wire WE = sdram_cmd_reg[0];

reg [1:0]sdram_BA;
reg [12:0]sdram_add;
reg [15:0]sdram_datout;
reg dout_en ;
wire [15:0]sdram_dq = dout_en ? sdram_datout : 16'hzzzz ;


reg [14:0]sta_cnt;
reg [4:0]t_cnt;

reg init_done;
reg modesetdone;

reg [23:0] w_addr;
reg [23:0] r_addr;
reg read_ram;
reg write_ram;
reg reading;
reg writing;

reg [15:0]write_buf[0:31];

wire [1:0]write_block = w_addr[4:3];
wire [4:0]write_buf_add = w_addr[4:0];

wire [15:0]data2ram = write_buf[write_buf_add];

reg [15:0]read_buf[0:31];
wire [1:0]read_block = r_addr[4:3];
wire [4:0]read_buf_add = r_addr[4:0];

wire [4:0] dis_addr = addr[4:0];
wire [1:0] dis_block = addr[4:3];

reg v_start;

// make some fake data to ram
reg [2:0]clk20m;
reg [18:0] addr2ram;
wire [4:0] addr2ram_buf = addr2ram[4:0];
wire [1:0] addr2ram_block = addr2ram[4:3];

always@(posedge dclk) clk20m <= clk20m + 1 ;

reg bit_sel ;
reg [7:0] high_8bit ;

reg [9:0] discnt ;

always@(posedge clk) begin
	if(lep_framestart) begin
		lep_buf_addr <= 0 ;
		lep_pix_cnt  <= 0 ;
	end
	//else if(lep_dat_pclk) begin
	else if(res_val) begin
		lep_buf_addr <= (lep_buf_addr < 159) ? lep_buf_addr + 1'b1 : 0 ;
		//lep_buf[lep_buf_addr] <= lep_dat ;
		lep_buf[lep_buf_addr] <= { resdat[7:3] , resdat[7:2] , resdat[7:3] } ;
		
		lep_pix_cnt  <= lep_pix_cnt + 1 ;
	end
end

reg [18:0] w_pixcnt ;

wire [15:0] lep_dat_out = lep_buf[discnt] ;

always@(posedge clk) begin
	
	if(lep_framestart) begin
		discnt <= 0 ;
		addr2ram <= 0 ;
		w_pixcnt <= 0 ;
	end
	else begin

		if(discnt > 159) begin

			write_buf[addr2ram_buf] <= 16'h001f ;
					
			addr2ram <= addr2ram + 1 ;
			
			discnt <= (discnt < 639) ? discnt + 1 : 0 ;
			
		end
		
		else if(lep_pix_cnt[18:4] != w_pixcnt[18:4]) begin
			
			w_pixcnt <= w_pixcnt + 1 ;
			
			write_buf[addr2ram_buf] <= lep_dat_out ;
			
			addr2ram <= addr2ram + 1 ;
			
			discnt <= discnt + 1 ;
			
		end
		
	end
end
// -----------------------------

always@(posedge clk100m_dq) begin
	if((t_cnt > 4)&&(t_cnt < 13)&&(reading)) read_buf[read_buf_add] <= sdram_dq ;
end

reg dis_vs;
reg [1:0] stop;
reg camvs;

always@(negedge clk100m) 
if(locked)begin
		
		if(modesetdone)begin           // normal work
			sta_cnt <= (sta_cnt == 1506) ? 0 : sta_cnt + 1 ;
			
			if(sta_cnt == 1506) t_cnt <= 0 ;
			else t_cnt <= (t_cnt == 23) ? 0 : t_cnt + 1 ;
			
			if(sta_cnt == 1500) begin
				sdram_cmd_reg <= SDRAM_AUTOREF ;
			end
			else if(sta_cnt < 1500)begin        // normal wirte/read cycles
			
				if(t_cnt == 0) begin
					
					//if(read_ram) begin
					if((r_addr < 8)|(read_block != dis_block)) begin
						sdram_cmd_reg <= SDRAM_BANKACTROW ; // bank & row address active
						sdram_BA <= r_addr[23:22] ; // if read data , apply the read_data_address
						sdram_add <= r_addr[21:9] ;
						reading <= 1 ;
						writing <= 0 ;
					end
					else begin
						sdram_cmd_reg <= SDRAM_NOP ;
						reading <= 0 ;
						writing <= 0 ;
					end
					
				end
				else if(t_cnt == 2) begin
					if(reading) begin              // if read data , apply the read_data_address
						sdram_cmd_reg <= SDRAM_READCOL ;
						sdram_add <= {3'b000 , r_addr[8:0]} ;
					end
					else sdram_cmd_reg <= SDRAM_NOP ;
				end
				else if(t_cnt == 10) begin                       // precharge to exit the current cycle
					if(reading | writing) sdram_cmd_reg <= SDRAM_PRECHAR ;
					else sdram_cmd_reg <= SDRAM_NOP ;
					sdram_add <= {3'b010 , sdram_add[8:0]} ;   // all banks
					dout_en <= 0 ;                             // disable output 
				end
				
				else if(t_cnt == 12) begin
					//if(write_ram)begin
					if(addr2ram_block != write_block) begin
						sdram_cmd_reg <= SDRAM_BANKACTROW ; // bank & row address active
						sdram_BA <= w_addr[23:22] ;         // if write data , apply the write_data_address
						sdram_add <= w_addr[21:9] ;
						writing <= 1 ;
						reading <= 0 ;
					end
					else begin
						sdram_cmd_reg <= SDRAM_NOP ;
						reading <= 0 ;
						writing <= 0 ;
					end
				end
				else if(t_cnt == 14) begin
					if(writing)begin                      // if write data , apply the write_data_address
						sdram_cmd_reg <= SDRAM_WRTECOL ;
						sdram_add <= {3'b000 , w_addr[8:0]} ;
						dout_en <= 1 ;                            // enable output 
						//sdram_datout <= data2ram ;
					end
					else sdram_cmd_reg <= SDRAM_NOP ;
				end
				else if(t_cnt == 22) begin
					if(reading | writing) sdram_cmd_reg <= SDRAM_PRECHAR ;
					else sdram_cmd_reg <= SDRAM_NOP ;
					sdram_add <= {3'b010 , sdram_add[8:0]} ;   // all banks
					dout_en <= 0 ;                             // disable output 
				end
				else sdram_cmd_reg <= SDRAM_NOP ;
			end
			else sdram_cmd_reg <= SDRAM_NOP ;
			
			if(lep_framestart) w_addr <= 0 ;
			else if((t_cnt > 13)&&(t_cnt < 22)&&(writing)) begin
				w_addr <= w_addr + 1 ;                    // write buf addr add
				sdram_datout <= data2ram ;                // apply data 
			end
			
			dis_vs <= vs ;
			
			if(vs&(dis_vs == 0)) v_start <= 1 ;                              // frame start delay for read_ram reset
			else if(read_block) v_start <= 0 ;
			
			if(vs&(dis_vs == 0)) r_addr <= 0 ;
			else if((t_cnt > 3)&&(t_cnt < 12)&&(reading)) r_addr <= r_addr + 1 ;
			
		end
		
		else if(init_done)begin        // wait for init done

			if(sta_cnt == 18) begin
				sta_cnt <= 0 ;
				t_cnt <= 0 ;
				modesetdone <= 1 ;
			end
			else begin
				sta_cnt <= sta_cnt + 1 ;
			end
			
			if(sta_cnt == 0) begin
				sdram_cmd_reg <= SDRAM_PRECHAR ;
				sdram_add <= 13'h1fff ;
				sdram_BA <= 2'b11 ;
			end
			else if((sta_cnt == 2)||(sta_cnt == 9)) sdram_cmd_reg <= SDRAM_AUTOREF ;
			else if(sta_cnt == 16) begin
				sdram_cmd_reg <= SDRAM_SETMODE ;
				sdram_add <= {3'b0,1'b0,2'b0,3'b010,1'b0,3'b011} ;    // LSB 3bit for burst length, 010 : 4, 011:8
				sdram_BA <= 2'b00 ;
			end
			else sdram_cmd_reg <= SDRAM_NOP ;
				
		end
		
		else begin                     // wait for boot done
			if(sta_cnt == 20000) begin
				init_done <= 1 ;
				sta_cnt <= 0 ;
			end
			else sta_cnt <= sta_cnt + 1 ;
		end
		
end
else begin
	sta_cnt <= 0 ;
	modesetdone <= 0 ;
	init_done <= 0 ;
	sdram_cke <= 1 ;
	sdram_cmd_reg <= SDRAM_NOP ;
	dout_en <= 0 ;
	
	read_ram <= 0 ;
	reading  <= 0 ;
	write_ram<= 0 ;
	writing  <= 0 ;
	
	stop <= 0 ;
	
end


// VGA display part
//reg[17:0] disdat ;
wire [15:0] disdat = read_buf[dis_addr];
assign r = ( flag==1 ? {disdat[15:11],1'bz} : 0 );
assign g = ( flag==1 ? disdat[10:5] : 0 );
assign b = ( flag==1 ? {disdat[4:0],1'bz} : 0 );


//Hsync clock generator
always@(posedge dclk)begin
	if (count_h == 800)
		count_h <= 0;
	else
		count_h <= count_h+1;
end

//Vsync clock generator
always@(posedge dclk)begin
	if (count_v == 525) count_v <= 0;
	else if (count_h == 800) count_v <= count_v+1;
	
	//if((count_h == 217)||(count_h == 1016)) disdat <= {6'h3f , 6'h0 , 6'h0} ;
	//else if((count_v == 28)||(count_v == 626)) disdat <= {6'h0 , 6'h3f , 6'h0} ;
	//else disdat <= {6'h0 , 6'h0 , 6'h3f} ;
	
end

//Hsync and Vsync generator.
always@(posedge dclk)begin
	if (count_h == 0) hs <= 0;
	if (count_v == 2) vs <= 1;
	if (count_h == 96) hs <= 1;
	if (count_v == 0) vs <= 0;
	if (count_v > 35 && count_v < 524)begin
		if ((count_h > 144) && (count_h < 785)) begin
			flag <= 1;
			addr <= addr+1;
		end 
		else flag <= 0 ;
	end 
	else addr<=0;
end

endmodule

module lepton(
					input  wire        clk ,
					input  wire        lep_go_in ,
					output wire        spiclk ,
					output wire        spics  ,
					input  wire        spimiso,
					output wire        lep_dat_pclk ,
					output wire        lep_framestart,
					output wire [15:0] lep_dat,
					output reg  [7:0]  result,
					output wire        res_val
					
);

reg [5:0]  clkcnt ;
reg [15:0] dat_in  ;
reg [6:0]  bit16_cnt;
reg [7:0]  pac_cnt ;
reg [7:0]  pac_cnt_local ;
reg [2:0]  seg_cnt ;
reg        pac_ok  ;

reg [15:0] errcnt ;
wire out_rdy = ((errcnt < 38399) || (errcnt > 57599)) ? 0 : 1 ;

reg [23:0] out_cnt ;
wire lep_sync = (out_cnt < 5000000) ? 1 : 0 ;

wire lep_go = lep_go_in & (~lep_sync) ;

assign spiclk = ((clkcnt > 1) && (clkcnt < 33)) ? clkcnt[0] : 1 ;
assign spics  = ((clkcnt > 0) && (clkcnt < 34)) ? 0 : 1 ;

assign lep_dat      = dat_in ;

wire lep_dat_pclk_inter = ((clkcnt == 34) && (bit16_cnt > 1)) ? pac_ok : 0 ;
assign lep_dat_pclk = ( out_rdy ) ? lep_dat_pclk_inter : 0 ;

assign lep_framestart = (clkcnt > 34) && (seg_cnt == 4) && (pac_cnt == 0) && (bit16_cnt == 1) && pac_ok ;

always@(posedge clk) begin
	if(lep_framestart | (~lep_go)) errcnt <= 0 ;
	else if(lep_dat_pclk_inter) errcnt <= (errcnt < 57611) ? errcnt + 1 : errcnt ;
	
	if(lep_dat_pclk_inter && (errcnt == 57605)) out_cnt <= 0 ;
	else out_cnt <= lep_sync ? out_cnt + 1 : out_cnt ;
	
end

always@(posedge clk) begin

	if(lep_go) begin

		clkcnt <= (clkcnt < 35) ? clkcnt + 1 : 0 ;
		
		if(~spiclk) begin
			dat_in <= {dat_in[14:0],spimiso} ;
		end
		
		else if(clkcnt == 35) begin
			
			bit16_cnt <= (bit16_cnt < 81) ? bit16_cnt + 1 : 0 ;
			
			case(bit16_cnt)
				0 : if(dat_in[11:8] == 15) pac_ok <= 0 ;
					 else begin
						pac_ok       <= 1 ;
						
						pac_cnt      <= dat_in[5:0] ;
						
						if(dat_in[5:0] == 0) pac_cnt_local <= 0 ;
						else pac_cnt_local <= (pac_cnt_local < 59) ? pac_cnt_local + 1 : 0 ;
						
						if(dat_in[5:0] == 20) seg_cnt <= dat_in[14:12] ;
						
					 end
				
			endcase
			
		end
		
	end
	
	else begin
		clkcnt        <= 0 ;
		bit16_cnt     <= 0 ;
		seg_cnt       <= 0 ;
		pac_ok        <= 0 ;
		pac_cnt       <= 0 ;
		pac_cnt_local <= 0 ;
	end
	
end

reg [15:0] maxval ;
reg [15:0] minval ;
reg [15:0] maxval_last ;
reg [15:0] minval_last ;
reg [15:0] dat2jud ;
reg [3:0]  step ;

wire [15:0] max2min = maxval_last - minval_last ;
reg [14:0] c_val ;

wire judres = (dat2jud > c_val) ? 1 : 0 ;
//reg [7:0] result ;

reg del1cle ;
//wire res_val = (step == 1) ;
assign res_val = ((step == 1) && del1cle) ;



always@(posedge clk) begin
	if(lep_framestart) begin
		maxval_last <= maxval ;
		minval_last <= minval ;
		maxval <= 0 ;
		minval <= 16'hffff ;
		del1cle <= 0 ;
	end
	else if(lep_dat_pclk) begin
		if(lep_dat > maxval) maxval <= lep_dat ;
		if(lep_dat < minval) minval <= lep_dat ;
		
		if(lep_dat > minval_last) dat2jud <= lep_dat - minval_last ;
		else dat2jud <= 0 ;
		
		c_val <= { 1'b0 , max2min[15:1] } ;
		step <= 9 ;
		
	end
	else if(step > 1) begin
		step <= step - 1 ;
		if(judres) dat2jud <= dat2jud - c_val ;
		result <= { result[6:0] , judres } ;
		c_val <= { 1'b0 , c_val[14:1] } ;
	end
	else if(step) begin
		step <= step - 1 ;
		del1cle <= 1 ;
	end
	
end

endmodule

