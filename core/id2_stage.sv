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
    // Debug (async) request - SUBSYSTEM
    input logic debug_req_i,

    // Inputs from ID stage
    input  logic [CVA6Cfg.NrIssuePorts-1:0]              decoded_instr_valid_i,
    // input  scoreboard_entry_t [CVA6Cfg.NrIssuePorts-1:0] decoded_instr_i,
    // input  scoreboard_entry_t [CVA6Cfg.NrIssuePorts-1:0] decoded_instr_i_prev,
    // input  logic [CVA6Cfg.NrIssuePorts-1:0][31:0]        orig_instr_i,
    // input  logic [CVA6Cfg.NrIssuePorts-1:0]              is_ctrl_flow_i,

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
    output logic [CVA6Cfg.NrIssuePorts-1:0]              rvfi_is_compressed_o,
    //******************** rajout *************************//
    // instruction is compressed (from compressed_decoder to decoder)
    input logic [CVA6Cfg.NrIssuePorts-1:0]         is_compressed_dec_i,
    input logic [CVA6Cfg.NrIssuePorts-1:0]         is_macro_instr_i,
    input logic [CVA6Cfg.NrIssuePorts-1:0]         is_zcmt_instr_i,
    input logic [CVA6Cfg.NrIssuePorts-1:0]         is_illegal_dec_i,
    input logic [CVA6Cfg.NrIssuePorts-1:0][31:0]   instruction_dec_i,
    input logic                                    is_last_macro_instr_i,
    input logic                                    is_double_rd_macro_instr_i,
    input logic [CVA6Cfg.XLEN-1:0]                 jump_address_i,
    input fetch_entry_t [CVA6Cfg.NrIssuePorts-1:0] fetch_entry_i,

    // Current privilege level - CSR_REGFILE
    input riscv::priv_lvl_t priv_lvl_i,
    // Current virtualization mode - CSR_REGFILE
    input logic v_i,
    // Floating point extension status - CSR_REGFILE
    input riscv::xs_t fs_i,
    // Floating point extension virtual status - CSR_REGFILE
    input riscv::xs_t vfs_i,
    // Floating point dynamic rounding mode - CSR_REGFILE
    input logic [2:0] frm_i,
    // Vector extension status - CSR_REGFILE
    input riscv::xs_t vs_i,
    // Level sensitive (async) interrupts - SUBSYSTEM
    input logic [1:0] irq_i,
    // Interrupt control status - CSR_REGFILE
    input irq_ctrl_t irq_ctrl_i,
    // Is current mode debug ? - CSR_REGFILE
    input logic debug_mode_i,
    // Trap virtual memory - CSR_REGFILE
    input logic tvm_i,
    // Timeout wait - CSR_REGFILE
    input logic tw_i,
    // Virtual timeout wait - CSR_REGFILE
    input logic vtw_i,
    // Trap sret - CSR_REGFILE
    input logic tsr_i,
    // Hypervisor user mode - CSR_REGFILE
    input logic hu_i
);
  typedef struct packed {
    logic              valid;
    scoreboard_entry_t sbe;
    logic [31:0]       orig_instr;
    logic              is_ctrl_flow;
  } issue_struct_t;
  issue_struct_t [CVA6Cfg.NrIssuePorts-1:0] issue_n, issue_q;

  //rajout à à cabler.
  logic              [CVA6Cfg.NrIssuePorts-1:0]       is_control_flow_instr;
  scoreboard_entry_t [CVA6Cfg.NrIssuePorts-1:0]       decoded_instruction;
  logic              [CVA6Cfg.NrIssuePorts-1:0]       decoded_instruction_valid;
  logic              [CVA6Cfg.NrIssuePorts-1:0][31:0] orig_instr;

  // ---------------------------------------------------------
  // 1 Decode and emit instruction to issue stage
  // ---------------------------------------------------------

  for (genvar i = 0; i < CVA6Cfg.NrIssuePorts; i++) begin
    decoder #(
        .CVA6Cfg(CVA6Cfg),
        .branchpredict_sbe_t(branchpredict_sbe_t),
        .exception_t(exception_t),
        .irq_ctrl_t(irq_ctrl_t),
        .scoreboard_entry_t(scoreboard_entry_t),
        .interrupts_t(interrupts_t),
        .INTERRUPTS(INTERRUPTS)
    ) decoder_i (
        .debug_req_i,
        .irq_ctrl_i,
        .irq_i,
        .pc_i                      (fetch_entry_i[i].address),
        .is_compressed_i           (is_compressed_dec_i[i]),
        .is_macro_instr_i          (is_macro_instr_i[i]),
        .is_zcmt_i                 (is_zcmt_instr_i[i]),
        .is_last_macro_instr_i     (is_last_macro_instr_i),
        .is_double_rd_macro_instr_i(is_double_rd_macro_instr_i),
        .jump_address_i            (jump_address_i),
        .is_illegal_i              (is_illegal_dec_i[i]),
        .instruction_i             (instruction_dec_i[i]),
        .compressed_instr_i        (fetch_entry_i[i].instruction[15:0]),
        .branch_predict_i          (fetch_entry_i[i].branch_predict),
        .ex_i                      (fetch_entry_i[i].ex),
        .priv_lvl_i                (priv_lvl_i),
        .v_i                       (v_i),
        .debug_mode_i              (debug_mode_i),
        .fs_i,
        .vfs_i,
        .frm_i,
        .vs_i,
        .tvm_i,
        .tw_i,
        .vtw_i,
        .tsr_i,
        .hu_i,
        .instruction_o             (decoded_instruction[i]),
        .orig_instr_o              (orig_instr[i]),
        .is_control_flow_instr_o   (is_control_flow_instr[i])
    );
  end

  // ------------------
  // 2 Pipeline Register
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
          decoded_instruction[0],
          orig_instr[0],
          is_control_flow_instr[0]
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