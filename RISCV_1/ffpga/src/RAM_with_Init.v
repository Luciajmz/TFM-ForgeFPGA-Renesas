module RAM_with_Init #(
    parameter ADDR_WIDTH = 7 // Debe coincidir con el top_forgefpga (7)
)(
    input wire clk,
    input wire [ADDR_WIDTH-1:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] wmask, 
    input wire wen,
    output reg [31:0] rdata
);

    reg [31:0] mem [0:(2**ADDR_WIDTH)-1];

    initial begin
        $readmemh("C:/workspace/RISCV/tfm_lucia/sw/program.hex", mem);
    end

    always @(posedge clk) begin
        if (wen) begin
            if (wmask[0]) mem[addr][7:0]   <= wdata[7:0];
            if (wmask[1]) mem[addr][15:8]  <= wdata[15:8];
            if (wmask[2]) mem[addr][23:16] <= wdata[23:16];
            if (wmask[3]) mem[addr][31:24] <= wdata[31:24];
        end
        rdata <= mem[addr];
    end
endmodule
