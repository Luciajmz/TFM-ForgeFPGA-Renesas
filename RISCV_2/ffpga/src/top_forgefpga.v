(* top *)
module top_forgefpga (
    (* iopad_external_pin, clkbuf_inhibit *) input wire clk_50mhz,
    (* iopad_external_pin *) input wire reset_n,
    (* iopad_external_pin *) input wire uart_rx,   // Entrada desde RealTerm
    (* iopad_external_pin *) output wire uart_tx,  // Salida hacia RealTerm
    (* iopad_external_pin *) output wire debug_led,
    
    // Pines de Output Enable obligatorios
    (* iopad_external_pin *) output wire clk_50mhz_oe,
    (* iopad_external_pin *) output wire reset_n_oe,
    (* iopad_external_pin *) output wire uart_rx_oe,
    (* iopad_external_pin *) output wire uart_tx_oe,
    (* iopad_external_pin *) output wire debug_led_oe,

    // Seales fsicas de la BRAM Hard IP (Para el I/O Planner)
    (* iopad_external_pin *) output wire [8:0] bram0_waddr,
    (* iopad_external_pin *) output wire [8:0] bram0_raddr,
    (* iopad_external_pin *) output wire [8:0] bram1_waddr,
    (* iopad_external_pin *) output wire [8:0] bram1_raddr,
    (* iopad_external_pin *) output wire [8:0] bram2_waddr,
    (* iopad_external_pin *) output wire [8:0] bram2_raddr,
    (* iopad_external_pin *) output wire [8:0] bram3_waddr,
    (* iopad_external_pin *) output wire [8:0] bram3_raddr,
    (* iopad_external_pin *) output wire [7:0] bram0_wdata,
    (* iopad_external_pin *) output wire bram0_wen,
    (* iopad_external_pin *) input  wire [7:0] bram0_rdata,
    (* iopad_external_pin *) output wire [7:0] bram1_wdata,
    (* iopad_external_pin *) output wire bram1_wen,
    (* iopad_external_pin *) input  wire [7:0] bram1_rdata,
    (* iopad_external_pin *) output wire [7:0] bram2_wdata,
    (* iopad_external_pin *) output wire bram2_wen,
    (* iopad_external_pin *) input  wire [7:0] bram2_rdata,
    (* iopad_external_pin *) output wire [7:0] bram3_wdata,
    (* iopad_external_pin *) output wire bram3_wen,
    (* iopad_external_pin *) input  wire [7:0] bram3_rdata,
    (* iopad_external_pin *) output wire bram_clk
);

    // 1. Configuracin de direccin de pines
    assign clk_50mhz_oe = 1'b1; // Entrada
    assign reset_n_oe   = 1'b1; // Entrada
    assign uart_rx_oe   = 1'b1; // Entrada
    assign uart_tx_oe   = 1'b1; // Salida
    assign debug_led_oe = 1'b1; // Salida

    // 2. Divisor de Reloj para CPU y UART TX (50 MHz / 16 = 3.125 MHz)
    reg [3:0] clk_div = 0;
    always @(posedge clk_50mhz) clk_div <= clk_div + 1;
    wire cpu_clk = clk_div[3];

    // 3. Seales del Bootloader
    wire boot_mode_active;
    wire cpu_reset_n;
    wire [6:0] boot_addr;
    wire [31:0] boot_wdata;
    wire [3:0] boot_wmask;
    wire boot_wen;

    UART_Bootloader #(.ADDR_WIDTH(7)) bootloader (
        .clk_50mhz(clk_50mhz),
        .reset_n(reset_n),
        .uart_rx(uart_rx),
        .boot_addr(boot_addr),
        .boot_wdata(boot_wdata),
        .boot_wmask(boot_wmask),
        .boot_wen(boot_wen),
        .cpu_reset_n(cpu_reset_n),
        .boot_mode_active(boot_mode_active)
    );

    // 4. Seales de la CPU
    wire [31:0] cpu_mem_addr, cpu_mem_wdata, pc_val;
    wire [3:0] cpu_mem_wmask;
    wire cpu_mem_rstrb;
    reg  [31:0] cpu_mem_rdata;
    reg  cpu_mem_rbusy, cpu_mem_wbusy;
    
    // Decodificador de direcciones
    wire is_ram  = (cpu_mem_addr[31:28] == 4'h0);
    wire is_uart = (cpu_mem_addr == 32'h40000000);
    wire cpu_mem_wen = (cpu_mem_wmask != 4'b0000);

    FemtoRV32 #(
        .RESET_ADDR(32'h00000000),
        .ADDR_WIDTH(32) 
    ) cpu (
        .clk(cpu_clk),
        .pc_debug(pc_val),    
        .reset(cpu_reset_n),    // FemtoRV32 necesita 0 para resetearse[cite: 4]
        .mem_addr(cpu_mem_addr),
        .mem_wdata(cpu_mem_wdata),
        .mem_wmask(cpu_mem_wmask),
        .mem_rdata(cpu_mem_rdata),
        .mem_rstrb(cpu_mem_rstrb),
        .mem_rbusy(cpu_mem_rbusy),
        .mem_wbusy(cpu_mem_wbusy)
    );

    // 5. El Multiplexor Maestro (El rbitro de la BRAM)
    wire [6:0] final_bram_addr  = boot_mode_active ? boot_addr  : cpu_mem_addr[8:2];
    wire [31:0] final_bram_wdata= boot_mode_active ? boot_wdata : cpu_mem_wdata;
    wire [3:0] final_bram_wmask = boot_mode_active ? boot_wmask : cpu_mem_wmask;
    wire final_bram_wen         = boot_mode_active ? boot_wen   : (cpu_mem_wen & is_ram);
    wire [31:0] bram_rdata_out;

    BRAM_32bit_Wrapper #(.ADDR_WIDTH(7)) ram_wrapper (
        .clk(clk_50mhz), // Usamos 50MHz para que el bootloader escriba rpido
        .addr(final_bram_addr),
        .wdata(final_bram_wdata),
        .wmask(final_bram_wmask),
        .wen(final_bram_wen),
        .rdata(bram_rdata_out), 
        
        .bram0_waddr(bram0_waddr), .bram0_raddr(bram0_raddr),
        .bram1_waddr(bram1_waddr), .bram1_raddr(bram1_raddr),
        .bram2_waddr(bram2_waddr), .bram2_raddr(bram2_raddr),
        .bram3_waddr(bram3_waddr), .bram3_raddr(bram3_raddr),
        .bram0_wdata(bram0_wdata), .bram0_wen(bram0_wen), .bram0_rdata(bram0_rdata),
        .bram1_wdata(bram1_wdata), .bram1_wen(bram1_wen), .bram1_rdata(bram1_rdata),
        .bram2_wdata(bram2_wdata), .bram2_wen(bram2_wen), .bram2_rdata(bram2_rdata),
        .bram3_wdata(bram3_wdata), .bram3_wen(bram3_wen), .bram3_rdata(bram3_rdata),
        .bram_clk(bram_clk)
    );

    // 6. Instancia de la UART de Transmisin
    wire uart_busy;
    UART_TX #(
        .CLK_FREQ(3125000), 
        .BAUD_RATE(115200)
    ) puerto_serie_tx (
        .clk(cpu_clk),
        .data(cpu_mem_wdata[7:0]), 
        .write_en(is_uart & cpu_mem_wen & !boot_mode_active), 
        .tx(uart_tx),
        .busy(uart_busy)
    );

    // 7. Lgica de lectura del bus para la CPU
    always @(*) begin
        cpu_mem_rdata = 32'h00000000;
        cpu_mem_rbusy = 1'b0; 
        cpu_mem_wbusy = 1'b0;

        if (is_ram) begin
            cpu_mem_rdata = bram_rdata_out;
        end else if (is_uart) begin
            cpu_mem_wbusy = uart_busy; 
        end
    end
    
    // 8. LED de Estado: Encendido si estamos en Bootloader, parpadea si la CPU ejecuta
    assign debug_led = boot_mode_active ? 1'b1 : pc_val[2];

endmodule

// =========================================================================
// MDULO 1: Bootloader UART
// =========================================================================
module UART_Bootloader #(
    parameter ADDR_WIDTH = 7
)(
    input wire clk_50mhz,
    input wire reset_n,
    input wire uart_rx, 
    output reg [ADDR_WIDTH-1:0] boot_addr,
    output reg [31:0] boot_wdata,
    output reg [3:0] boot_wmask,
    output reg boot_wen,
    output reg cpu_reset_n,
    output reg boot_mode_active 
);
    reg [8:0] rx_baud_counter = 0;
    reg [3:0] rx_bit_idx = 0;
    reg [7:0] rx_byte = 0;
    reg rx_byte_ready = 0;
    reg [1:0] rx_state = 0;
    
    always @(posedge clk_50mhz) begin
        if (!reset_n) begin
            rx_state <= 0;
            rx_byte_ready <= 0;
        end else begin
            rx_byte_ready <= 0; 
            case (rx_state)
                0: begin 
                    if (uart_rx == 0) begin
                        rx_baud_counter <= 217; 
                        rx_state <= 1;
                    end
                end
                1: begin 
                    if (rx_baud_counter == 0) begin
                        rx_baud_counter <= 433; 
                        rx_bit_idx <= 0;
                        rx_state <= 2;
                    end else rx_baud_counter <= rx_baud_counter - 1;
                end
                2: begin 
                    if (rx_baud_counter == 0) begin
                        rx_byte[rx_bit_idx] <= uart_rx;
                        rx_baud_counter <= 433;
                        rx_bit_idx <= rx_bit_idx + 1;
                        if (rx_bit_idx == 7) rx_state <= 3;
                    end else rx_baud_counter <= rx_baud_counter - 1;
                end
                3: begin 
                    if (rx_baud_counter == 0) begin
                        rx_byte_ready <= 1; 
                        rx_state <= 0;
                    end else rx_baud_counter <= rx_baud_counter - 1;
                end
            endcase
        end
    end

    reg [1:0] byte_counter = 0;
    reg [31:0] word_buffer = 0;
    parameter GO_COMMAND = 32'hDEADBEEF;

    always @(posedge clk_50mhz) begin
        if (!reset_n) begin
            boot_addr <= 0;
            boot_wdata <= 0;
            boot_wmask <= 0;
            boot_wen <= 0;
            cpu_reset_n <= 0; // CPU Apagada[cite: 4]
            boot_mode_active <= 1; 
            byte_counter <= 0;
            word_buffer <= 0;
        end else begin
            boot_wen <= 0; 
            if (boot_mode_active && rx_byte_ready) begin
                case (byte_counter)
                    0: word_buffer[7:0]   <= rx_byte;
                    1: word_buffer[15:8]  <= rx_byte;
                    2: word_buffer[23:16] <= rx_byte;
                    3: word_buffer[31:24] <= rx_byte;
                endcase
                
                if (byte_counter == 3) begin
                    byte_counter <= 0;
                    if ({rx_byte, word_buffer[23:0]} == GO_COMMAND) begin
                        boot_mode_active <= 0; 
                        cpu_reset_n <= 1;      // Despertar CPU[cite: 4]
                    end else begin
                        boot_wdata <= {rx_byte, word_buffer[23:0]};
                        boot_wmask <= 4'b1111; 
                        boot_wen <= 1;         
                        boot_addr <= boot_addr + 1; 
                    end
                end else byte_counter <= byte_counter + 1;
            end
        end
    end
endmodule

// =========================================================================
// MÓDULO 2: BRAM 32-bit Wrapper (Solución a entradas duplicadas)
// =========================================================================
module BRAM_32bit_Wrapper #(
    parameter ADDR_WIDTH = 7 
)(
    input wire clk,
    input wire [ADDR_WIDTH-1:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] wmask,
    input wire wen,
    output wire [31:0] rdata,
    
    // Ahora cada BRAM tiene su propio cable de dirección en el top
    output wire [8:0] bram0_waddr, output wire [8:0] bram0_raddr,
    output wire [8:0] bram1_waddr, output wire [8:0] bram1_raddr,
    output wire [8:0] bram2_waddr, output wire [8:0] bram2_raddr,
    output wire [8:0] bram3_waddr, output wire [8:0] bram3_raddr,

    output wire [7:0] bram0_wdata, output wire bram0_wen, input wire [7:0] bram0_rdata,
    output wire [7:0] bram1_wdata, output wire bram1_wen, input wire [7:0] bram1_rdata,
    output wire [7:0] bram2_wdata, output wire bram2_wen, input wire [7:0] bram2_rdata,
    output wire [7:0] bram3_wdata, output wire bram3_wen, input wire [7:0] bram3_rdata,
    output wire bram_clk
);
    assign bram_clk = clk;
    
    // El "truco": Le damos la misma dirección a las 4, pero con nombres de cable distintos
    wire [8:0] addr_ext = {2'b00, addr};
    
    assign bram0_waddr = addr_ext; assign bram0_raddr = addr_ext;
    assign bram1_waddr = addr_ext; assign bram1_raddr = addr_ext;
    assign bram2_waddr = addr_ext; assign bram2_raddr = addr_ext;
    assign bram3_waddr = addr_ext; assign bram3_raddr = addr_ext;

    assign bram0_wdata = wdata[7:0];
    assign bram1_wdata = wdata[15:8];
    assign bram2_wdata = wdata[23:16];
    assign bram3_wdata = wdata[31:24];

    assign bram0_wen = ~(wen & wmask[0]); 
    assign bram1_wen = ~(wen & wmask[1]);
    assign bram2_wen = ~(wen & wmask[2]);
    assign bram3_wen = ~(wen & wmask[3]);

    assign rdata = {bram3_rdata, bram2_rdata, bram1_rdata, bram0_rdata};
endmodule