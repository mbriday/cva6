// empty second decode

module id2_stage #(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type branchpredict_sbe_t = logic,
    parameter type dcache_req_i_t = logic,
    parameter type dcache_req_o_t = logic,
    parameter type exception_t = logic,
    parameter type fetch_entry_t = logic,
    parameter type jvt_t = logic,
    parameter type irq_ctrl_t = logic,
    parameter type scoreboard_entry_t = logic,
    parameter type interrupts_t = logic,
    parameter interrupts_t INTERRUPTS = '0,
    parameter type x_compressed_req_t = logic,
    parameter type x_compressed_resp_t = logic
) (
    // Subsystem Clock - SUBSYSTEM
    input logic clk_i,
    // Asynchronous reset active low - SUBSYSTEM
    input logic rst_ni,
    // Fetch flush request - CONTROLLER
    input logic flush_i,

    // Inputs from ID stage
    input  logic [CVA6Cfg.NrIssuePorts-1:0]              decoded_instr_valid_i,
    input  scoreboard_entry_t [CVA6Cfg.NrIssuePorts-1:0] decoded_instr_i,
    input  scoreboard_entry_t [CVA6Cfg.NrIssuePorts-1:0] decoded_instr_i_prev,
    input  logic [CVA6Cfg.NrIssuePorts-1:0][31:0]        orig_instr_i,
    input  logic [CVA6Cfg.NrIssuePorts-1:0]              is_ctrl_flow_i,

    // Output to ID stage (ack)
    output logic [CVA6Cfg.NrIssuePorts-1:0]              decoded_instr_ack_o,

    // Outputs to ISSUE stage
    output logic [CVA6Cfg.NrIssuePorts-1:0]              decoded_instr_valid_o,
    output scoreboard_entry_t [CVA6Cfg.NrIssuePorts-1:0] decoded_instr_o,
    output scoreboard_entry_t [CVA6Cfg.NrIssuePorts-1:0] decoded_instr_o_prev,
    output logic [CVA6Cfg.NrIssuePorts-1:0][31:0]        orig_instr_o,
    output logic [CVA6Cfg.NrIssuePorts-1:0]              is_ctrl_flow_o,

    // Input from ISSUE stage (ack signal)
    input  logic [CVA6Cfg.NrIssuePorts-1:0]              decoded_instr_ack_i,

    // input/output to RVFI stage
    input  logic [CVA6Cfg.NrIssuePorts-1:0]              rvfi_is_compressed_i,
    output logic [CVA6Cfg.NrIssuePorts-1:0]              rvfi_is_compressed_o
);
  typedef struct packed {
    logic              valid;
    scoreboard_entry_t sbe;
    logic [31:0]       orig_instr;
    logic              is_ctrl_flow;
  } issue_struct_t;
  issue_struct_t [CVA6Cfg.NrIssuePorts-1:0] issue_n, issue_q;

  // ------------------
  // 3. Pipeline Register
  // ------------------
  for (genvar i = 0; i < CVA6Cfg.NrIssuePorts; i++) begin
    assign decoded_instr_o[i] = issue_q[i].sbe;
    assign decoded_instr_o_prev[i] = CVA6Cfg.FpgaAlteraEn ? issue_n[i].sbe : '0;
    assign decoded_instr_valid_o[i] = issue_q[i].valid;
    assign is_ctrl_flow_o[i] = issue_q[i].is_ctrl_flow;
    assign orig_instr_o[i] = issue_q[i].orig_instr;
  end

  always_comb begin
    issue_n = issue_q;
    decoded_instr_ack_o = '0;

    // Clear the valid flag if issue has acknowledged the instruction
    if (decoded_instr_ack_i[0]) issue_n[0].valid = 1'b0;
    
    // if the instruction is not valid and the instruction in previous stage is valid, then
    //copy the instruction to the pipeline register
    if (!issue_n[0].valid && decoded_instr_valid_i[0]) begin
      decoded_instr_ack_o[0] = 1'b1; // acknowledge the instruction
      issue_n[0] = '{
          decoded_instr_valid_i[0],
          decoded_instr_i[0],
          orig_instr_i[0],
          is_ctrl_flow_i[0]
      };
    end
    // invalidate the pipeline register on a flush
    if (flush_i) issue_n[0].valid = 1'b0;
  end

  // -------------------------
  // Registers (ID2 <-> Issue)
  // -------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      issue_q <= '0;
      rvfi_is_compressed_o <= '0;
    end else begin
      issue_q <= issue_n;
      rvfi_is_compressed_o <= rvfi_is_compressed_i;
    end
  end
endmodule