module UART_TX #(
    parameter CLK_FREQ = 10000000, // Reloj de la Forge (Ej: 10 MHz)
    parameter BAUD_RATE = 115200   // Velocidad típica del puerto serie
)(
    input wire clk,
    input wire [7:0] data, // Los 8 bits (un carácter) que manda el RISC-V
    input wire write_en,   // Pulso que envía el RISC-V cuando quiere escribir
    output reg tx,         // ESTE PIN VA FÍSICAMENTE AL EXTERIOR
    output reg busy        // Le avisa al RISC-V si está ocupado mandando algo
);

    localparam CYCLES_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    reg [3:0] bit_idx;
    reg [15:0] clk_count;
    reg [9:0] shift_reg;   // Registro de desplazamiento (Start + 8 Data + Stop)

    initial begin
        tx = 1'b1; // En reposo, la línea serie siempre está en HIGH
        busy = 1'b0;
    end

    always @(posedge clk) begin
        // Si el RISC-V manda un dato y no estamos ocupados...
        if (write_en && !busy) begin
            shift_reg <= {1'b1, data, 1'b0}; // Empaquetamos: Stop(1), Datos, Start(0)
            busy <= 1'b1;
            clk_count <= 0;
            bit_idx <= 0;
        end 
        // Si estamos transmitiendo...
        else if (busy) begin
            if (clk_count == CYCLES_PER_BIT - 1) begin
                clk_count <= 0;
                tx <= shift_reg[0]; // Mandamos el bit menos significativo
                shift_reg <= {1'b1, shift_reg[9:1]}; // Desplazamos los bits
                bit_idx <= bit_idx + 1;
                
                if (bit_idx == 9) busy <= 1'b0; // Terminamos de enviar
            end else begin
                clk_count <= clk_count + 1;
            end
        end
    end
endmodule