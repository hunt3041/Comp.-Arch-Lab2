// riscvsingle.sv

// RISC-V single-cycle processor
// From Section 7.6 of Digital Design & Computer Architecture
// 27 April 2020
// David_Harris@hmc.edu 
// Sarah.Harris@unlv.edu

// run 210
// Expect simulator to print "Simulation succeeded"
// when the value 25 (0x19) is written to address 100 (0x64)

//   Instruction  opcode    funct3    funct7
//   add          0110011   000       0000000
//   sub          0110011   000       0100000
//   and          0110011   111       0000000
//   or           0110011   110       0000000
//   slt          0110011   010       0000000
//   addi         0010011   000       immediate
//   andi         0010011   111       immediate
//   ori          0010011   110       immediate
//   slti         0010011   010       immediate
//   beq          1100011   000       immediate
//   lw	          0000011   010       immediate
//   sw           0100011   010       immediate
//   jal          1101111   immediate immediate
//   bge          1100011   101       immediate

module testbench();

   logic        clk;
   logic        reset;
   logic        PCReady;

   logic [31:0] WriteData;
   logic [31:0] DataAdr;
   logic        MemWrite;
   logic        MemStrobe;

   // instantiate device to be tested
   top dut(clk, reset, PCReady, WriteData, DataAdr, MemWrite, MemStrobe);

   initial
     begin
	string memfilename;
        memfilename = {"../riscvtest/srai.memfile"};
        $readmemh(memfilename, dut.imem.RAM);
     end

   
   // initialize test
   initial
     begin
	reset <= 1; # 22; reset <= 0;
     end

   // generate clock to sequence tests
   always
     begin
	clk <= 1; # 5; clk <= 0; # 5;
     end

   // check results
   always @(negedge clk)
     begin
	if(MemWrite) begin
           if(DataAdr === 100 & WriteData === 25) begin
              $display("Simulation succeeded");
              //$stop;
           end else if (DataAdr !== 96) begin
              $display("Simulation failed");
              //$stop;
           end
	end
     end
endmodule // testbench

module top (input  logic        clk, reset, PCReady,
	    output logic [31:0] WriteData, DataAdr,
	    output logic 	MemWrite,
      output logic  MemStrobe);
   
   logic [31:0] 		PC, Instr, ReadData, RegData;
   
   // instantiate processor and memories
   riscvsingle rv32single (clk, reset, PCReady, PC, Instr, MemWrite, DataAdr,
			   WriteData, ReadData, MemStrobe, RegData);
   imem imem (PC, Instr);
   dmem dmem (clk, MemWrite, DataAdr, WriteData, ReadData);
   
endmodule // top

module riscvsingle (input  logic        clk, reset, PCReady,
		    output logic [31:0] PC,
		    input  logic [31:0] Instr,
		    output logic 	MemWrite,
		    output logic [31:0] ALUResult, WriteData,
		    input  logic [31:0] ReadData,
        output logic        MemStrobe,
        output logic [31:0] RegData
        );
   
   logic 				ALUSrc, AUIPC, RegWrite, Jump, Jalr, Zero, branchYN; 
   logic [1:0] 				ResultSrc;
   logic [2:0]        ImmSrc;
   logic [1:0]        PCSrc;
   logic [3:0] 				ALUControl;
   
   
   
   controller c (Instr[6:0], Instr[14:12], Instr[30], Zero, branchYN,
		 ResultSrc, MemWrite, PCSrc,
		 ALUSrc, AUIPC, RegWrite, Jump, Jalr,
		 ImmSrc, ALUControl, MemStrobe);
   datapath dp (clk, reset, PCReady, ResultSrc, PCSrc,
		ALUSrc, AUIPC, RegWrite,
		ImmSrc, ALUControl,
		Zero, branchYN, PC, Instr,
		ALUResult, WriteData, ReadData, RegData);
   
endmodule // riscvsingle

module controller (input  logic [6:0] op,
		   input  logic [2:0] funct3,
		   input  logic       funct7b5,
		   input  logic       Zero,
       input  logic       branchYN,
		   output logic [1:0] ResultSrc,
		   output logic       MemWrite,
		   output logic [1:0] PCSrc, 
       output logic       ALUSrc, AUIPC,
		   output logic       RegWrite, Jump, Jalr,
		   output logic [2:0] ImmSrc,
		   output logic [3:0] ALUControl,
       output logic       MemStrobe);
   
   logic [1:0] 			      ALUOp;
   logic 			      Branch;
    logic            PC;
   maindec md (op, ResultSrc, MemWrite, Branch,
	       ALUSrc, AUIPC, RegWrite, Jump, Jalr, ImmSrc, ALUOp, MemStrobe);
   aludec ad (op[5], funct3, funct7b5, op[2], ALUOp, ALUControl);

   assign PCSrc = (Jalr)? 2'b10 : ((branchYN | Jump)? 2'b01 : 2'b00); // edit for jalr and 2-bit PC mux

endmodule // controller 

//handles all branch instructions
module branchalu (input logic [31:0] a, b,
                  input logic branch,
                  input logic [2:0] funct3,
                  output logic branchYN);

  logic [31:0] a_flip, b_flip;

  assign  a_flip = {~a[31], a[30:0]};
  assign  b_flip = {~b[31], b[30:0]};
  
  always_comb
  if(branch)  begin
    case(funct3)
    3'b000: branchYN = (a == b);
    3'b001: branchYN = (a != b);
    3'b100: branchYN = (a_flip < b_flip);
    3'b101: branchYN = (a_flip >= b_flip);
    3'b110: branchYN = (a < b);
    3'b111: branchYN = (a >= b);
    default: branchYN = 1'b0;
    endcase
  end
  
  else begin
    branchYN = 1'b0;
  end
   
  
endmodule //branchalu

module maindec (input  logic [6:0] op,
		output logic [1:0] ResultSrc,
		output logic 	   MemWrite,
		output logic 	   Branch, ALUSrc, AUIPC,
		output logic 	   RegWrite, Jump, Jalr,
		output logic [2:0] ImmSrc,
		output logic [1:0] ALUOp,
    output logic       MemStrobe);
   
   logic [14:0] 		   controls;
   
   assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
	   ResultSrc, Branch, ALUOp, Jump, Jalr, AUIPC, MemStrobe} = controls;
   
   always_comb
     case(op)
       // RegWrite_ImmSrc_ALUSrc_MemWrite_ResultSrc_Branch_ALUOp_Jump_Jalr?_AUIPC?_MemStrobe
       7'b0000011: controls = 15'b1_000_1_0_01_0_00_0_0_0_1; // lw,lb,lh,lbu,lhu
       7'b0100011: controls = 15'b0_001_1_1_00_0_00_0_0_0_1; // sw,sb,sh
       7'b0110011: controls = 15'b1_xxx_0_0_00_0_10_0_0_0_0; // R–type
       7'b1100011: controls = 15'b0_010_0_0_00_1_01_0_0_0_0; // B-type
       7'b0010011: controls = 15'b1_100_1_0_00_0_10_0_0_0_0; // I–type 
       7'b1101111: controls = 15'b1_011_0_0_10_0_00_1_0_0_0; // jal
       7'b1100111: controls = 15'b1_000_1_0_10_0_00_0_1_0_0; // jalr
       7'b0110111: controls = 15'b1_111_1_0_00_0_11_0_0_0_0; // lui
       7'b0010111: controls = 15'b1_111_1_0_00_0_00_0_0_1_0; // auipc
       default: controls = 15'bx_xxx_x_x_xx_x_xx_x_x_x_x; // ???
     endcase // case (op)
   
endmodule // maindec

module aludec (input  logic       opb5,
	       input  logic [2:0] funct3,
	       input  logic 	    funct7b5,
         input  logic       opb2,
	       input  logic [1:0] ALUOp,
	       output logic [3:0] ALUControl);
   
   logic 			  RtypeSub;
   
   assign RtypeSub = funct7b5 & opb5; // TRUE for R–type subtract
   always_comb
     case(ALUOp)
       2'b00: ALUControl = 4'b0000; // addition
       2'b01: ALUControl = 4'b0001; // subtraction
       2'b11: ALUControl = 4'b1010; //lui
       default: case(funct3) // R–type or I–type ALU
		  3'b000: if (RtypeSub & ~opb2)
		    ALUControl = 4'b0001; // sub
      // else if (opb2 & opb5)
      //   ALUControl = 4'b1010; //lui
		  else
		    ALUControl = 4'b0000; // add, addi

		  3'b010: ALUControl = 4'b0101; // slt, slti
		  3'b110: ALUControl = 4'b0011; // or, ori
		  3'b111: ALUControl = 4'b0010; // and, andi
      3'b100: ALUControl = 4'b0110; // xor, xori
      3'b001: ALUControl = 4'b0111; // sll, slli
      3'b011: ALUControl = 4'b1100; // sltu
      3'b101: if(funct7b5)
        ALUControl = 4'b1000; // sra, srai
      else 
        ALUControl = 4'b1111; // srl, srli
		  default: ALUControl = 4'bxxxx; // ???
		endcase // case (funct3)       
     endcase // case (ALUOp)
   
endmodule // aludec

module datapath (input  logic        clk, reset, PCReady,
		 input  logic [1:0]  ResultSrc,
		 input  logic [1:0]	 PCSrc, 
     input  logic        ALUSrc,AUIPC,
		 input  logic 	     RegWrite,
		 input  logic [2:0]  ImmSrc,
		 input  logic [3:0]  ALUControl,
		 output logic 	     Zero, branchYN,
		 output logic [31:0] PC,
		 input  logic [31:0] Instr,
		 output logic [31:0] ALUResult, WriteData,
		 input  logic [31:0] ReadData,
     output  logic [31:0] RegData);
   
   logic [31:0] 		     PCNext, PCPlus4, PCTarget;
   logic [31:0] 		     ImmExt;
   logic [31:0] 		     SrcA, SrcB;
   //logic [31:0] 		     Result;
   logic [31:0]          SrcAmuxresult;
   //logic [31:0]          RegData;
   logic [31:0]          DataShort;
   
   // next PC logic
   //flopenr #(32) pcreg (clk, reset, PCReady, PCNext, PC);
   flopr #(32) pcreg (clk, reset, PCNext, PC);
   adder  pcadd4 (PC, 32'd4, PCPlus4);
   adder  pcaddbranch (PC, ImmExt, PCTarget);
   mux3 #(32)  pcmux (PCPlus4, PCTarget, ALUResult, PCSrc, PCNext);
   // register file logic
   regfile  rf (clk, RegWrite, Instr[19:15], Instr[24:20],
	       Instr[11:7], RegData, SrcA, DataShort);
   Data_shortener_stores datawrite (Instr[6:0], Instr[14:12], DataShort, WriteData);
   extend  ext (Instr[31:7], ImmSrc, ImmExt);
   // ALU logic
   mux2 #(32)  srcbmux (WriteData, ImmExt, ALUSrc, SrcB);
   mux2 #(32)  Srcamux (SrcA, (PCPlus4 - 4), AUIPC, SrcAmuxresult);
   alu  alu (SrcAmuxresult, SrcB, Instr[14:12], Instr[6:0], ALUControl, ALUResult, Zero, branchYN);
   //mux3 #(32) resultmux (ALUResult, ReadData, PCPlus4,ResultSrc, Result);
   Data_shortener_loads resultmux (ALUResult, ReadData, PCPlus4, ResultSrc, RegData, Instr);
   

endmodule // datapath

// handles all store instructions. It shortens the data in the case of a sb or sh.
module Data_shortener_stores (input logic [6:0] op,
                        input logic [2:0] funct3,
                        input logic [31:0] DataShort,
                        output logic [31:0] WriteData);
    always_comb
    if((op == 7'b0100011)) 
      case(funct3)
      3'b000: WriteData = {{24{DataShort[7]}}, DataShort[7:0]};
      3'b001: WriteData = {{16{DataShort[15]}}, DataShort[15:0]};
      default: WriteData = DataShort;
      endcase
    else 
      WriteData = DataShort;
    
endmodule

// handles all load instructions. It shortens the data in the case of a sb or sh.
module Data_shortener_loads (input logic [31:0]ALUResult, ReadData, PCPlus4, //look at immediate extend for sign extending 
      input logic [1:0] ResultSrc, 
      output logic [31:0] Result,
      input logic [31:0] Instr);

  logic [2:0] funct3;
  logic [6:0] opcode;
  logic [31:0]  muxresult;

  assign funct3 = Instr[14:12];
  assign opcode = Instr[6:0];

  mux3 #(32) resultmux (ALUResult, ReadData, PCPlus4,ResultSrc, muxresult);

    always_comb
    if((opcode == 7'b0000011)) 
      case(funct3)
      3'b000: Result = {{24{muxresult[7]}}, muxresult[7:0]};
      3'b001: Result = {{16{muxresult[15]}}, muxresult[15:0]};
      3'b100: Result = 32'h000000ff & muxresult;
      3'b101: Result = 32'h0000ffff & muxresult;
      default: Result = muxresult;
      endcase
    else 
    Result = muxresult;
    
endmodule

module adder (input  logic [31:0] a, b,
	      output logic [31:0] y);
   
   assign y = a + b;
   
endmodule

module extend (input  logic [31:7] instr,
	       input  logic [2:0]  immsrc,
	       output logic [31:0] immext);
   
   always_comb
     case(immsrc)
       // loads
       3'b000: immext = {{20{instr[31]}}, instr[31:20]};
       //all other I-type
       3'b100: if((instr[14:12] == 3'b101) && instr[30])
               immext = {{27{0}}, instr[24:20]};
               else
               immext = {{20{instr[31]}}, instr[31:20]};
       // S−type (stores)
       3'b001:  immext = {{20{instr[31]}}, instr[31:25], instr[11:7]};
       // B−type (branches)
       3'b010:  immext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};       
       // J−type (jal)
       3'b011:  immext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
       // U-type (lui, auipc)
       3'b111:  immext = {{12{instr[31]}}, instr[31:12]} << 12;
       default: immext = 32'bx; // undefined
     endcase // case (immsrc)
   
endmodule // extend

module flopr #(parameter WIDTH = 8)
   (input  logic             clk, reset,
    input logic [WIDTH-1:0]  d,
    output logic [WIDTH-1:0] q);
   
   always_ff @(posedge clk, posedge reset)
     if (reset) q <= 0;
     else  q <= d;
   
endmodule // flopr

module flopenr #(parameter WIDTH = 8)
   (input  logic             clk, reset, en,
    input logic [WIDTH-1:0]  d,
    output logic [WIDTH-1:0] q);
   
   always_ff @(posedge clk, posedge reset)
     if (reset)  q <= 0;
     else if (en) q <= d;
   
endmodule // flopenr

module mux2 #(parameter WIDTH = 8)
   (input  logic [WIDTH-1:0] d0, d1,
    input logic 	     s,
    output logic [WIDTH-1:0] y);
   
  assign y = s ? d1 : d0;
   
endmodule // mux2

module mux3 #(parameter WIDTH = 8)
   (input  logic [WIDTH-1:0] d0, d1, d2,
    input logic [1:0] 	     s,
    output logic [WIDTH-1:0] y);
   
  assign y = s[1] ? d2 : (s[0] ? d1 : d0);
   
endmodule // mux3



module imem (input  logic [31:0] a,
	     output logic [31:0] rd);
   
   logic [31:0] 		 RAM[63:0];
   
   assign rd = RAM[a[31:2]]; // word aligned
   
endmodule // imem

module dmem (input  logic        clk, we,
	     input  logic [31:0] a, wd,
	     output logic [31:0] rd);
   
   logic [31:0] 		 RAM[255:0];
   
   assign rd = RAM[a[31:2]]; // word aligned
   always_ff @(posedge clk)
     if (we) RAM[a[31:2]] <= wd;
   
endmodule // dmem

module alu (input  logic [31:0] a, b,
            input logic  [2:0] funct3,
            input logic   [6:0] opcode,
            input  logic [3:0] 	alucontrol,
            output logic [31:0] result,
            output logic  zero, branchYN
            ); 

   logic [31:0] 	       condinvb, sum;
   logic 		       v;              // overflow
   logic 		       isAddSub;      // true when is add or subtract operation
   logic            branch;
   logic            gt, lt;

   assign branch = (opcode == 7'b1100011) & ((funct3 == 3'b000) | (funct3 == 3'b001) | (funct3 == 3'b100) | (funct3 == 3'b101) | (funct3 == 3'b110) | (funct3 == 3'b111));  
   assign condinvb = alucontrol[0] ? ~b : b;
   assign sum = a + condinvb + alucontrol[0];
   assign isAddSub = ~alucontrol[2] & ~alucontrol[1] |
                     ~alucontrol[1] & alucontrol[0];   

   always_comb
     case (alucontrol)
       4'b0000:  result = sum;         // add
       4'b0001:  result = sum;         // subtract
       4'b0010:  result = a & b;       // and
       4'b0011:  result = a | b;       // or
       4'b0101:  result = sum[31] ^ v; // slt  
       4'b0110:  result = a ^ b;       //xor, xori  
       4'b0111:  result = a << b;      // sll, slli 
       4'b1111:  result = a >> b;      // srl, srli  
       4'b1000:  result = $signed(a) >>> b; // sra, srai
       4'b1100:  result = a < b;       //slt, sltiu
       4'b1010:  result = 0 + b;       // lui
       default: result = 32'bx;
     endcase

    branchalu ba (a, b, branch, funct3, branchYN);

    assign zero = (result == 32'b0);
   assign v = ~(alucontrol[0] ^ a[31] ^ b[31]) & (a[31] ^ sum[31]) & isAddSub;
   
endmodule // alu




module regfile (input  logic        clk, 
		input  logic 	    we3, 
		input  logic [4:0]  a1, a2, a3, 
		input  logic [31:0] wd3, 
		output logic [31:0] rd1, rd2);

   logic [31:0] 		    rf[31:0];

   // three ported register file
   // read two ports combinationally (A1/RD1, A2/RD2)
   // write third port on rising edge of clock (A3/WD3/WE3)
   // register 0 hardwired to 0

   always_ff @(posedge clk)
     if (we3) rf[a3] <= wd3;	

   assign rd1 = (a1 != 0) ? rf[a1] : 0;
   assign rd2 = (a2 != 0) ? rf[a2] : 0;
   
endmodule // regfile

