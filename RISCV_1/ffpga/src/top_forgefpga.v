module top_forgefpga (
    // 1. Pines principales (con los atributos que pide el manual)
    (* iopad_external_pin, clkbuf_inhibit *) input wire clk_50mhz,  // Reloj de la placa (50 MHz)
    (* iopad_external_pin *) input wire reset_n,                    // Tu PMOD
    (* iopad_external_pin *) output wire uart_tx,                   // Tu PMOD
    (* iopad_external_pin *) output wire debug_led,                 // LED de la placa
    
    // 2. Pines obligatorios de control de dirección (Output Enable)
    (* iopad_external_pin *) output wire clk_50mhz_oe,
    (* iopad_external_pin *) output wire reset_n_oe,
    (* iopad_external_pin *) output wire uart_tx_oe,
    (* iopad_external_pin *) output wire debug_led_oe
);
	
    // 3. Fijamos la dirección física de cada pin
    assign clk_50mhz_oe = 1'b1; // 0 = Entrada (apagamos salida)
    assign reset_n_oe   = 1'b1; // 0 = Entrada (apagamos salida)
    assign uart_tx_oe   = 1'b1; // 1 = Salida (encendemos salida)
    assign debug_led_oe = 1'b1; // 1 = Salida (encendemos salida)

    // 4. Divisor de Reloj: 50 MHz / 16 = 3.125 MHz
    reg [3:0] clk_div = 4'b0000;
    always @(posedge clk_50mhz) begin
        clk_div <= clk_div + 1;
    end
    wire clk = clk_div[3]; // ESTE es el reloj lento que usaremos para el resto del chip
    
    // 1. Cables del bus
    wire [31:0] mem_addr, mem_wdata, pc_val;
    wire [3:0]  mem_wmask;
    wire        mem_rstrb;
    reg  [31:0] mem_rdata;
    reg         mem_rbusy, mem_wbusy;

    // 2. CPU con el nuevo puerto pc_debug y ADDR_WIDTH a 32
    FemtoRV32 #(
        .RESET_ADDR(32'h00000000),
        .ADDR_WIDTH(32) 
    ) cpu (
        .clk(clk),
        .pc_debug(pc_val),    // Conectamos el nuevo puerto
        .reset(reset_n),      // El archivo dice: "set to 0 to reset" 
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wmask(mem_wmask),
        .mem_rdata(mem_rdata),
        .mem_rstrb(mem_rstrb),
        .mem_rbusy(mem_rbusy),
        .mem_wbusy(mem_wbusy)
    );

    // 3. Conexión de vida: el LED dependerá de un bit del PC
    assign debug_led = pc_val[2];

    // 3. Decodificador de direcciones y escritura
    wire ram_en  = (mem_addr[31:28] == 4'h0);   
    wire uart_en = (mem_addr == 32'h40000000);  
    wire uart_busy;
    
    // En esta versión, sabemos que hay escritura si la máscara no es cero
    wire mem_wen = (mem_wmask != 4'b0000); 

	// 4. Instanciamos tu Memoria BRAM
    wire [31:0] ram_rdata;
    RAM_with_Init #(
        .ADDR_WIDTH(7) // ¡REDUCIDO! 128 palabras (512 bytes)
    ) memoria (
        .clk(clk),
        .addr(mem_addr[8:2]), // Ajustado a 7 bits (del bit 8 al 2)
        .wdata(mem_wdata),
        .wmask(mem_wmask),
        .wen(ram_en & mem_wen),
        .rdata(ram_rdata)
    );

    // 5. Instanciamos la UART 
    UART_TX #(
        .CLK_FREQ(3125000), 
        .BAUD_RATE(115200)
    ) puerto_serie (
        .clk(clk),
        .data(mem_wdata[7:0]), 
        .write_en(uart_en & mem_wen), 
        .tx(uart_tx),
        .busy(uart_busy)
    );

    // 6. Multiplexor de lectura y control de pausa del CPU
    always @(*) begin
        mem_rdata = 32'h00000000;
        mem_rbusy = 1'b0; // Por defecto la memoria responde instantáneamente
        mem_wbusy = 1'b0;

        if (ram_en) begin
            mem_rdata = ram_rdata;
        end else if (uart_en) begin
            // Si el procesador escribe en la UART y está ocupada mandando un carácter, congela el CPU.
            mem_wbusy = uart_busy; 
        end
    end
    
endmodule