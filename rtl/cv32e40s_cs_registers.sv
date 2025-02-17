// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

////////////////////////////////////////////////////////////////////////////////
// Engineer:       Sven Stucki - svstucki@student.ethz.ch                     //
//                                                                            //
// Additional contributions by:                                               //
//                 Andreas Traber - atraber@iis.ee.ethz.ch                    //
//                 Michael Gautschi - gautschi@iis.ee.ethz.ch                 //
//                 Davide Schiavone - pschiavo@iis.ee.ethz.ch                 //
//                 Andrea Bettati - andrea.bettati@studenti.unipr.it          //
//                 Øystein Knauserud - oystein.knauserud@silabs.com           //
//                 Øivind Ekelund - oivind.ekelund@silabs.com                 //
//                                                                            //
// Design Name:    Control and Status Registers                               //
// Project Name:   RI5CY                                                      //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Control and Status Registers (CSRs) loosely following the  //
//                 RiscV draft priviledged instruction set spec (v1.9)        //
//                 Added Floating point support                               //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

module cv32e40s_cs_registers import cv32e40s_pkg::*;
#(
  parameter              LIB              = 0,
  parameter m_ext_e      M_EXT            = M,
  parameter bit          X_EXT            = 0,
  parameter logic [31:0] X_MISA           =  32'h00000000,
  parameter logic [1:0]  X_ECS_XS         =  2'b00, // todo: implement related mstatus bitfields (but only if X_EXT = 1)
  parameter bit          ZC_EXT           = 0, // todo: remove parameter once fully implemented
  parameter bit          SMCLIC           = 0,
  parameter int          SMCLIC_ID_WIDTH  = 5,
  parameter int          NUM_MHPMCOUNTERS = 1,
  parameter int          PMP_NUM_REGIONS  = 0,
  parameter int          PMP_GRANULARITY  = 0,
  parameter pmpncfg_t    PMP_PMPNCFG_RV[PMP_NUM_REGIONS-1:0] = '{default:PMPNCFG_DEFAULT},
  parameter logic [31:0] PMP_PMPADDR_RV[PMP_NUM_REGIONS-1:0] = '{default:32'h0},
  parameter mseccfg_t    PMP_MSECCFG_RV                      = MSECCFG_DEFAULT,
  parameter lfsr_cfg_t   LFSR0_CFG        = LFSR_CFG_DEFAULT,
  parameter lfsr_cfg_t   LFSR1_CFG        = LFSR_CFG_DEFAULT,
  parameter lfsr_cfg_t   LFSR2_CFG        = LFSR_CFG_DEFAULT,
  parameter int          DBG_NUM_TRIGGERS = 1, // todo: implement support for DBG_NUM_TRIGGERS != 1
  parameter int unsigned MTVT_ADDR_WIDTH  = 26
)
(
  // Clock and Reset
  input  logic            clk,
  input  logic            rst_n,
  input  logic            scan_cg_en_i,

  // IDs
  input  logic [31:0]     mhartid_i,
  input  logic  [3:0]     mimpid_patch_i,

  // MTVEC
  output logic [24:0]     mtvec_addr_o,
  output logic  [1:0]     mtvec_mode_o,

  // MTVT
  output logic [MTVT_ADDR_WIDTH-1:0]     mtvt_addr_o,

  // Cycle Count
  output logic [MHPMCOUNTER_WIDTH-1:0] mcycle_o,

  // Used for mtvec address
  input  logic [31:0]     mtvec_addr_i,
  input  logic            csr_mtvec_init_i,

  // IF/ID pipeline
  input if_id_pipe_t      if_id_pipe_i,
  input logic             sys_en_id_i,
  input logic             sys_mret_id_i,

  // ID/EX pipeline
  input id_ex_pipe_t      id_ex_pipe_i,

  // EX/WB pipeline
  input  ex_wb_pipe_t     ex_wb_pipe_i,

  // From controller FSM
  input  ctrl_fsm_t       ctrl_fsm_i,

  // To controller bypass logic
  output logic            csr_counter_read_o,
  output logic            csr_mnxti_read_o,

  // Interface to registers (SRAM like)
  output logic [31:0]     csr_rdata_o,

  // To EX stage
  output logic            csr_illegal_o, // 1'b1 for illegal CSR access.

  // To WB stage
  output logic            clic_pa_valid_o,   // CSR read data is an address to a function pointer
  output logic [31:0]     clic_pa_o,         // Address to CLIC function pointer

  // Interrupts
  output logic [31:0]     mie_o,
  input  logic [31:0]     mip_i,
  output logic            m_irq_enable_o,
  output logic [7:0]      mintthresh_o,
  output mintstatus_t     mintstatus_o,
  output mcause_t         mcause_o,

  input  logic                       mnxti_irq_pending_i,
  input  logic [SMCLIC_ID_WIDTH-1:0] mnxti_irq_id_i,
  input  logic [7:0]                 mnxti_irq_level_i,

  output logic [31:0]     mepc_o,

  // PMP CSR's
  output pmp_csr_t        csr_pmp_o,

  // Read Error
  output logic            csr_err_o,

  // LFSR lockup
  output logic            lfsr_lockup_o,
  input  logic            lfsr_shift_if_i,
  input  logic            lfsr_shift_id_i,

  // Xsecure control
  output xsecure_ctrl_t   xsecure_ctrl_o,

  // CSR write strobes
  output logic            csr_wr_in_wb_flush_o,

  // debug
  output logic [31:0]     dpc_o,
  output dcsr_t           dcsr_o,
  output logic            trigger_match_o,

  output privlvlctrl_t    priv_lvl_if_ctrl_o,
  output privlvl_t        priv_lvl_lsu_o,
  output privlvl_t        priv_lvl_o,
  output privlvl_t        priv_lvl_clic_ptr_o,

  output mstatus_t        mstatus_o,

  input  logic [31:0]     pc_if_i,
  input  logic            ptr_in_if_i
);

  localparam logic [31:0] CORE_MISA =
    (32'(1)          <<  2) | // C - Compressed extension
    (32'(1)          <<  8) | // I - RV32I/64I/128I base ISA
    (32'(M_EXT == M) << 12) | // M - Integer Multiply/Divide extension
    (32'(1)          << 20) | // U - User mode implemented
    (32'(0)          << 23) | // X - Non-standard extensions present
    (32'(MXL)        << 30); // M-XLEN

  localparam logic [31:0] MISA_VALUE = CORE_MISA | (X_EXT ? X_MISA : 32'h0000_0000);

  localparam PMP_ADDR_WIDTH = (PMP_GRANULARITY > 0) ? 33 - PMP_GRANULARITY : 32;

  logic [31:0] mimpid;

  // CSR update logic
  logic [31:0] csr_wdata_int;
  logic [31:0] csr_rdata_int;
  logic        csr_we_int;

  // Interrupt control signals
  logic [31:0] mepc_q, mepc_n;
  logic mepc_we;
  logic mepc_rd_error;

  // Trigger
  logic [15:0] tinfo_types;
  logic [31:0] tmatch_control_q, tmatch_control_n;
  logic [31:0] tmatch_value_q, tmatch_value_n;
  // Write enables
  logic tmatch_control_we;
  logic tmatch_value_we;
  logic tmatch_control_rd_error;
  logic tmatch_value_rd_error;
  // Debug
  dcsr_t       dcsr_q, dcsr_n;
  logic dcsr_we;
  logic dcsr_rd_error;
  logic [31:0] dcsr_rdata;
  logic [31:0] dpc_q, dpc_n;
  logic dpc_we;
  logic dpc_rd_error;

  logic [31:0] dscratch0_q, dscratch0_n;
  logic dscratch0_we, dscratch1_we;
  logic dscratch0_rd_error, dscratch1_rd_error;
  logic [31:0] dscratch1_q, dscratch1_n;

  logic [31:0] mscratch_q, mscratch_n;
  logic mscratch_we;
  logic mscratch_rd_error;

  jvt_t        jvt_q, jvt_n;
  logic        jvt_we, jvt_rd_error;

  mstatus_t mstatus_q, mstatus_n;
  logic mstatus_we;
  logic mstatus_rd_error;

  mcause_t mcause_q, mcause_n;
  logic mcause_we;
  logic mcause_rd_error;

  mtvec_t mtvec_n, mtvec_q;
  logic mtvec_we;
  logic mtvec_rd_error;

  logic [31:0] mcounteren_n, mcounteren_q;
  logic mcounteren_we;
  logic mcounteren_rd_error;

  mtvt_t       mtvt_n, mtvt_q;
  logic        mtvt_we, mtvt_rd_error;

  logic        mnxti_we;

  mintstatus_t mintstatus_q, mintstatus_n;
  logic        mintstatus_we, mintstatus_rd_error;

  logic [31:0] mintthresh_q, mintthresh_n;
  logic        mintthresh_we, mintthresh_rd_error;

  logic [31:0] mscratchcsw_q, mscratchcsw_n;
  logic        mscratchcsw_we;

  logic [31:0] mscratchcswl_q, mscratchcswl_n;
  logic        mscratchcswl_we;

  logic [31:0] mclicbase_q, mclicbase_n;
  logic        mclicbase_we;

  logic [31:0] mip;                     // Bits are masked according to IRQ_MASK
  logic [31:0] mie_q, mie_n;            // Bits are masked according to IRQ_MASK
  logic mie_we;
  logic mie_rd_error;

  pmpncfg_t                   pmpncfg_n[PMP_MAX_REGIONS];
  pmpncfg_t                   pmpncfg_q[PMP_MAX_REGIONS];
  logic [PMP_MAX_REGIONS-1:0] pmpncfg_we_int;
  logic [PMP_MAX_REGIONS-1:0] pmpncfg_we;
  logic [PMP_NUM_REGIONS-1:0] pmpncfg_locked;
  logic [PMP_NUM_REGIONS-1:0] pmpncfg_rd_error;
  logic [PMP_NUM_REGIONS-1:0] pmpncfg_wr_addr_match;
  logic [PMP_NUM_REGIONS-1:0] pmpncfg_warl_ignore_wr;
  logic [PMP_NUM_REGIONS-1:0] pmpaddr_wr_addr_match;

  logic [PMP_ADDR_WIDTH-1:0]  pmp_addr_n;
  logic [PMP_ADDR_WIDTH-1:0]  pmp_addr_q[PMP_MAX_REGIONS];
  logic [PMP_MAX_REGIONS-1:0] pmp_addr_we_int;
  logic [PMP_MAX_REGIONS-1:0] pmp_addr_we;
  logic [31:0]                pmp_addr_rdata[PMP_MAX_REGIONS];
  logic [PMP_NUM_REGIONS-1:0] pmp_addr_rd_error;

  mseccfg_t                   pmp_mseccfg_n;
  mseccfg_t                   pmp_mseccfg_q;
  logic                       pmp_mseccfg_we;
  logic                       pmp_mseccfg_rd_error;

  logic                       pmp_rd_error;

  privlvl_t                   priv_lvl_n, priv_lvl_q;
  logic                       priv_lvl_we;
  logic                       priv_lvl_error;
  logic [1:0]                 priv_lvl_q_int;
  logic                       umode_mcounteren_illegal_read;
  logic                       illegal_csr_write_priv, illegal_csr_read_priv;

  cpuctrl_t                   cpuctrl_n, cpuctrl_q;
  logic                       cpuctrl_we;
  logic                       cpuctrl_rd_error;

  logic [31:0]                secureseed0_n, secureseed1_n, secureseed2_n;
  logic                       secureseed0_we, secureseed1_we, secureseed2_we;

  // Performance Counter Signals
  logic [31:0] [MHPMCOUNTER_WIDTH-1:0] mhpmcounter_q;                    // performance counters
  logic [31:0] [MHPMCOUNTER_WIDTH-1:0] mhpmcounter_n;                    // performance counters next value
  logic [31:0] [1:0]                   mhpmcounter_we;                   // performance counters write enable
  logic [31:0] [31:0]                  mhpmevent_q, mhpmevent_n;         // event enable
  logic [31:0]                         mcountinhibit_q, mcountinhibit_n; // performance counter enable
  logic [NUM_HPM_EVENTS-1:0]           hpm_events;                       // events for performance counters
  logic [31:0] [MHPMCOUNTER_WIDTH-1:0] mhpmcounter_increment;            // increment of mhpmcounter_q
  logic [31:0]                         mhpmcounter_write_lower;          // write 32 lower bits of mhpmcounter_q
  logic [31:0]                         mhpmcounter_write_upper;          // write 32 upper bits mhpmcounter_q
  logic [31:0]                         mhpmcounter_write_increment;      // write increment of mhpmcounter_q

  // Local instr_valid
  logic instr_valid;

  csr_opcode_e csr_op;
  csr_num_e    csr_waddr;
  csr_num_e    csr_raddr;
  logic [31:0] csr_wdata;
  logic        csr_en_gated;
  logic        csr_wr_in_wb;
  logic        xsecure_csr_wr_in_wb;
  logic        pmp_csr_wr_in_wb;

  logic illegal_csr_read;  // Current CSR cannot be read
  logic illegal_csr_write; // Current CSR cannot be written

  // Local instr_valid for write portion (WB)
  assign instr_valid = ex_wb_pipe_i.instr_valid && !ctrl_fsm_i.kill_wb && !ctrl_fsm_i.halt_wb;

  // CSR access. Read in EX, write in WB
  // Setting csr_raddr to zero in case of unused csr to save power (alu_operand_b toggles a lot)
  assign csr_raddr = csr_num_e'((id_ex_pipe_i.csr_en && id_ex_pipe_i.instr_valid) ? id_ex_pipe_i.alu_operand_b[11:0] : 12'b0);

  // Not suppressing csr_waddr to zero when unused since its source are dedicated flipflops and would not save power as for raddr
  assign csr_waddr = csr_num_e'(ex_wb_pipe_i.csr_addr);
  assign csr_wdata = ex_wb_pipe_i.csr_wdata;

  assign csr_op    =  ex_wb_pipe_i.csr_op;

  // CSR write operations in WB, actual csr_we_int may still become 1'b0 in case of CSR_OP_READ
  assign csr_en_gated    = ex_wb_pipe_i.csr_en && instr_valid;

  // mip CSR
  assign mip = mip_i;

  // Combine all CSR Read error outputs
  assign csr_err_o = mstatus_rd_error ||
                     mtvec_rd_error   ||
                     pmp_rd_error     ||
                     cpuctrl_rd_error ||
                     dcsr_rd_error    ||
                     mie_rd_error     ||
                     mepc_rd_error;

  // mimpid CSR
  assign mimpid = {12'b0, MIMPID_MAJOR, 4'b0, MIMPID_MINOR, 4'b0, mimpid_patch_i};

  ////////////////////////////////////////
  // Determine if CSR access is illegal //
  // Both read and write validity is    //
  // checked in the first (EX) stage    //
  // Invalid writes will suppress ex_wb //
  // signals and avoid writing in WB    //
  ////////////////////////////////////////

  // Bits [9:8] in csr_addr indicate priviledge level needed to access CSR's.
  // The exception is access to perfomance counters from user mode, which is configured through mcounteren.
  assign illegal_csr_write_priv =  csr_raddr[9:8] > id_ex_pipe_i.priv_lvl;
  assign illegal_csr_read_priv  = (csr_raddr[9:8] > id_ex_pipe_i.priv_lvl) || umode_mcounteren_illegal_read;

  assign illegal_csr_write = (id_ex_pipe_i.csr_op != CSR_OP_READ) &&
                             (id_ex_pipe_i.csr_en) &&
                             ((csr_raddr[11:10] == 2'b11) || illegal_csr_write_priv); // Priv spec section 2.1

  assign csr_illegal_o = (id_ex_pipe_i.instr_valid && id_ex_pipe_i.csr_en) ? illegal_csr_write || illegal_csr_read || illegal_csr_read_priv : 1'b0;


  ////////////////////////////////////////////
  //   ____ ____  ____    ____              //
  //  / ___/ ___||  _ \  |  _ \ ___  __ _   //
  // | |   \___ \| |_) | | |_) / _ \/ _` |  //
  // | |___ ___) |  _ <  |  _ <  __/ (_| |  //
  //  \____|____/|_| \_\ |_| \_\___|\__, |  //
  //                                |___/   //
  ////////////////////////////////////////////

  // NOTE!!!: Any new CSR register added in this file must also be
  //   added to the valid CSR register list cv32e40s_decoder.v

  // read logic
  always_comb
  begin
    illegal_csr_read              = 1'b0;
    umode_mcounteren_illegal_read = 1'b0;
    csr_counter_read_o            = 1'b0;
    csr_mnxti_read_o   = 1'b0;

    case (csr_raddr)
      // jvt: Jump vector table
      CSR_JVT:  begin
        if (ZC_EXT) begin // todo: remove conditional once fully implemented
          csr_rdata_int = jvt_q;
        end else begin
          csr_rdata_int    = '0;
          illegal_csr_read = 1'b1;
        end
      end

      // mstatus: always M-mode, contains IE bit
      CSR_MSTATUS: csr_rdata_int = mstatus_q;

      // mstatush: All bits hardwired to 0
      CSR_MSTATUSH: csr_rdata_int = 'b0;

      // misa: machine isa register
      CSR_MISA: csr_rdata_int = MISA_VALUE;

      // mie: machine interrupt enable
      CSR_MIE: begin
        if (SMCLIC) begin
          // CLIC mode is assumed when SMCLIC = 1
          csr_rdata_int = '0;
        end else begin
         csr_rdata_int = mie_q;
        end
      end

      // mtvec: machine trap-handler base address
      CSR_MTVEC: csr_rdata_int = mtvec_q;
      // mcounteren: Counter enable registers
      CSR_MCOUNTEREN: csr_rdata_int = mcounteren_q;
      // mtvt: machine trap-handler vector table base address
      CSR_MTVT: begin
        if (SMCLIC) begin
          csr_rdata_int = mtvt_q;
        end else begin
          csr_rdata_int    = '0;
          illegal_csr_read = 1'b1;
        end
      end

      // mscratch: machine scratch
      CSR_MSCRATCH: csr_rdata_int = mscratch_q;

      // mepc: exception program counter
      CSR_MEPC: csr_rdata_int = mepc_q;

      // mcause: exception cause
      CSR_MCAUSE: begin
        if (SMCLIC) begin
          // CLIC mode is assumed when SMCLIC = 1
          // For CLIC, the mpp and mpie bits from mstatus
          // are readable via mcause
          csr_rdata_int = {
                            mcause_q[31:30],
                            mstatus_q.mpp,   // 29:28
                            mstatus_q.mpie,  // 27
                            mcause_q[26:0]
                          };
        end else begin
          csr_rdata_int = mcause_q;
        end
      end

      // mip: interrupt pending
      CSR_MIP: begin
        // CLIC mode is assumed when SMCLIC = 1
        if (SMCLIC) begin
          csr_rdata_int = '0;
        end else begin
          csr_rdata_int = mip;
        end
      end

      // mnxti: Next Interrupt Handler Address and Interrupt Enable
      CSR_MNXTI: begin
        if (SMCLIC) begin
          // The data read here is what will be used in the read-modify-write portion of the CSR access.
          // For mnxti, this is actually mstatus. The value written back to the GPR will be the address of
          // the function pointer to the interrupt handler. This is muxed in the WB stage.
          csr_rdata_int = mstatus_q;
          csr_mnxti_read_o = 1'b1;
        end else begin
          csr_rdata_int    = '0;
          illegal_csr_read = 1'b1;
        end
      end

      // mintstatus: Interrupt Status
      CSR_MINTSTATUS: begin
        if (SMCLIC) begin
          csr_rdata_int = mintstatus_q;
        end else begin
          csr_rdata_int    = '0;
          illegal_csr_read = 1'b1;
        end
      end

      // mintthresh: Interrupt-Level Threshold
      CSR_MINTTHRESH: begin
        if (SMCLIC) begin
          csr_rdata_int = mintthresh_q;
        end else begin
          csr_rdata_int    = '0;
          illegal_csr_read = 1'b1;
        end
      end

      // mscratchcsw: Scratch Swap for Multiple Privilege Modes
      CSR_MSCRATCHCSW: begin
        if (SMCLIC) begin
          csr_rdata_int = mscratchcsw_q;
        end else begin
          csr_rdata_int    = '0;
          illegal_csr_read = 1'b1;
        end
      end

      // mscratchcswl: Scratch Swap for Interrupt Levels
      CSR_MSCRATCHCSWL: begin
        if (SMCLIC) begin
          csr_rdata_int = mscratchcswl_q;
        end else begin
          csr_rdata_int    = '0;
          illegal_csr_read = 1'b1;
        end
      end

      // mclicbase: CLIC Base
      CSR_MCLICBASE: begin
        if (SMCLIC) begin
          csr_rdata_int = mclicbase_q;
        end else begin
          csr_rdata_int    = '0;
          illegal_csr_read = 1'b1;
        end
      end

      // mhartid: unique hardware thread id
      CSR_MHARTID: csr_rdata_int = mhartid_i;

      // mimpid: implementation id
      CSR_MIMPID: csr_rdata_int = mimpid;

      // mconfigptr: Pointer to configuration data structure. Read only, hardwired to 0
      CSR_MCONFIGPTR: csr_rdata_int = 'b0;

      // mvendorid: Machine Vendor ID
      CSR_MVENDORID: csr_rdata_int = {MVENDORID_BANK, MVENDORID_OFFSET};

      // marchid: Machine Architecture ID
      CSR_MARCHID: csr_rdata_int = MARCHID;

      // unimplemented, read 0 CSRs
        CSR_MTVAL :
          csr_rdata_int = 'b0;

      CSR_TSELECT,
        CSR_TDATA3,
        CSR_MCONTEXT,
        CSR_MSCONTEXT,
        CSR_TCONTROL:
              csr_rdata_int = 'b0; // Always read 0
      CSR_TDATA1:
              csr_rdata_int = tmatch_control_q;
      CSR_TDATA2:
              csr_rdata_int = tmatch_value_q;
      CSR_TINFO:
              csr_rdata_int = tinfo_types;

      CSR_DCSR: begin
              csr_rdata_int = dcsr_rdata;
              illegal_csr_read = !ctrl_fsm_i.debug_mode;
      end
      CSR_DPC: begin
              csr_rdata_int = dpc_q;
              illegal_csr_read = !ctrl_fsm_i.debug_mode;
      end
      CSR_DSCRATCH0: begin
              csr_rdata_int = dscratch0_q;
              illegal_csr_read = !ctrl_fsm_i.debug_mode;
      end
      CSR_DSCRATCH1: begin
              csr_rdata_int = dscratch1_q;
              illegal_csr_read = !ctrl_fsm_i.debug_mode;
      end

      // Hardware Performance Monitor
      CSR_MCYCLE,
      CSR_MINSTRET,
      CSR_MHPMCOUNTER3,
      CSR_MHPMCOUNTER4,  CSR_MHPMCOUNTER5,  CSR_MHPMCOUNTER6,  CSR_MHPMCOUNTER7,
      CSR_MHPMCOUNTER8,  CSR_MHPMCOUNTER9,  CSR_MHPMCOUNTER10, CSR_MHPMCOUNTER11,
      CSR_MHPMCOUNTER12, CSR_MHPMCOUNTER13, CSR_MHPMCOUNTER14, CSR_MHPMCOUNTER15,
      CSR_MHPMCOUNTER16, CSR_MHPMCOUNTER17, CSR_MHPMCOUNTER18, CSR_MHPMCOUNTER19,
      CSR_MHPMCOUNTER20, CSR_MHPMCOUNTER21, CSR_MHPMCOUNTER22, CSR_MHPMCOUNTER23,
      CSR_MHPMCOUNTER24, CSR_MHPMCOUNTER25, CSR_MHPMCOUNTER26, CSR_MHPMCOUNTER27,
      CSR_MHPMCOUNTER28, CSR_MHPMCOUNTER29, CSR_MHPMCOUNTER30, CSR_MHPMCOUNTER31,
      CSR_CYCLE,
      CSR_INSTRET,
      CSR_HPMCOUNTER3,
      CSR_HPMCOUNTER4,  CSR_HPMCOUNTER5,  CSR_HPMCOUNTER6,  CSR_HPMCOUNTER7,
      CSR_HPMCOUNTER8,  CSR_HPMCOUNTER9,  CSR_HPMCOUNTER10, CSR_HPMCOUNTER11,
      CSR_HPMCOUNTER12, CSR_HPMCOUNTER13, CSR_HPMCOUNTER14, CSR_HPMCOUNTER15,
      CSR_HPMCOUNTER16, CSR_HPMCOUNTER17, CSR_HPMCOUNTER18, CSR_HPMCOUNTER19,
      CSR_HPMCOUNTER20, CSR_HPMCOUNTER21, CSR_HPMCOUNTER22, CSR_HPMCOUNTER23,
      CSR_HPMCOUNTER24, CSR_HPMCOUNTER25, CSR_HPMCOUNTER26, CSR_HPMCOUNTER27,
      CSR_HPMCOUNTER28, CSR_HPMCOUNTER29, CSR_HPMCOUNTER30, CSR_HPMCOUNTER31: begin
        csr_rdata_int                 = mhpmcounter_q[csr_raddr[4:0]][31:0];
        umode_mcounteren_illegal_read = !mcounteren_q[csr_raddr[4:0]] && (id_ex_pipe_i.priv_lvl == PRIV_LVL_U);
        csr_counter_read_o            = 1'b1;
      end

      CSR_MCYCLEH,
      CSR_MINSTRETH,
      CSR_MHPMCOUNTER3H,
      CSR_MHPMCOUNTER4H,  CSR_MHPMCOUNTER5H,  CSR_MHPMCOUNTER6H,  CSR_MHPMCOUNTER7H,
      CSR_MHPMCOUNTER8H,  CSR_MHPMCOUNTER9H,  CSR_MHPMCOUNTER10H, CSR_MHPMCOUNTER11H,
      CSR_MHPMCOUNTER12H, CSR_MHPMCOUNTER13H, CSR_MHPMCOUNTER14H, CSR_MHPMCOUNTER15H,
      CSR_MHPMCOUNTER16H, CSR_MHPMCOUNTER17H, CSR_MHPMCOUNTER18H, CSR_MHPMCOUNTER19H,
      CSR_MHPMCOUNTER20H, CSR_MHPMCOUNTER21H, CSR_MHPMCOUNTER22H, CSR_MHPMCOUNTER23H,
      CSR_MHPMCOUNTER24H, CSR_MHPMCOUNTER25H, CSR_MHPMCOUNTER26H, CSR_MHPMCOUNTER27H,
      CSR_MHPMCOUNTER28H, CSR_MHPMCOUNTER29H, CSR_MHPMCOUNTER30H, CSR_MHPMCOUNTER31H,
      CSR_CYCLEH,
      CSR_INSTRETH,
      CSR_HPMCOUNTER3H,
      CSR_HPMCOUNTER4H,  CSR_HPMCOUNTER5H,  CSR_HPMCOUNTER6H,  CSR_HPMCOUNTER7H,
      CSR_HPMCOUNTER8H,  CSR_HPMCOUNTER9H,  CSR_HPMCOUNTER10H, CSR_HPMCOUNTER11H,
      CSR_HPMCOUNTER12H, CSR_HPMCOUNTER13H, CSR_HPMCOUNTER14H, CSR_HPMCOUNTER15H,
      CSR_HPMCOUNTER16H, CSR_HPMCOUNTER17H, CSR_HPMCOUNTER18H, CSR_HPMCOUNTER19H,
      CSR_HPMCOUNTER20H, CSR_HPMCOUNTER21H, CSR_HPMCOUNTER22H, CSR_HPMCOUNTER23H,
      CSR_HPMCOUNTER24H, CSR_HPMCOUNTER25H, CSR_HPMCOUNTER26H, CSR_HPMCOUNTER27H,
      CSR_HPMCOUNTER28H, CSR_HPMCOUNTER29H, CSR_HPMCOUNTER30H, CSR_HPMCOUNTER31H: begin
        csr_rdata_int                 = (MHPMCOUNTER_WIDTH == 64) ? mhpmcounter_q[csr_raddr[4:0]][63:32] : '0;
        umode_mcounteren_illegal_read = !mcounteren_q[csr_raddr[4:0]] && (id_ex_pipe_i.priv_lvl == PRIV_LVL_U);
        csr_counter_read_o            = 1'b1;
      end

      CSR_MCOUNTINHIBIT: csr_rdata_int = mcountinhibit_q;

      CSR_MHPMEVENT3,
      CSR_MHPMEVENT4,  CSR_MHPMEVENT5,  CSR_MHPMEVENT6,  CSR_MHPMEVENT7,
      CSR_MHPMEVENT8,  CSR_MHPMEVENT9,  CSR_MHPMEVENT10, CSR_MHPMEVENT11,
      CSR_MHPMEVENT12, CSR_MHPMEVENT13, CSR_MHPMEVENT14, CSR_MHPMEVENT15,
      CSR_MHPMEVENT16, CSR_MHPMEVENT17, CSR_MHPMEVENT18, CSR_MHPMEVENT19,
      CSR_MHPMEVENT20, CSR_MHPMEVENT21, CSR_MHPMEVENT22, CSR_MHPMEVENT23,
      CSR_MHPMEVENT24, CSR_MHPMEVENT25, CSR_MHPMEVENT26, CSR_MHPMEVENT27,
      CSR_MHPMEVENT28, CSR_MHPMEVENT29, CSR_MHPMEVENT30, CSR_MHPMEVENT31:
        csr_rdata_int = mhpmevent_q[csr_raddr[4:0]];


      CSR_PMPCFG0, CSR_PMPCFG1, CSR_PMPCFG2,  CSR_PMPCFG3,  CSR_PMPCFG4,  CSR_PMPCFG5,  CSR_PMPCFG6,  CSR_PMPCFG7,
      CSR_PMPCFG8, CSR_PMPCFG9, CSR_PMPCFG10, CSR_PMPCFG11, CSR_PMPCFG12, CSR_PMPCFG13, CSR_PMPCFG14, CSR_PMPCFG15:
        csr_rdata_int = {pmpncfg_q[6'(csr_raddr[3:0]*4 + 3)], pmpncfg_q[6'(csr_raddr[3:0]*4 + 2)],
                         pmpncfg_q[6'(csr_raddr[3:0]*4 + 1)], pmpncfg_q[6'(csr_raddr[3:0]*4 + 0)]};


      CSR_PMPADDR0,  CSR_PMPADDR1,  CSR_PMPADDR2,  CSR_PMPADDR3,  CSR_PMPADDR4,  CSR_PMPADDR5,  CSR_PMPADDR6,  CSR_PMPADDR7,
      CSR_PMPADDR8,  CSR_PMPADDR9,  CSR_PMPADDR10, CSR_PMPADDR11, CSR_PMPADDR12, CSR_PMPADDR13, CSR_PMPADDR14, CSR_PMPADDR15:
        csr_rdata_int = pmp_addr_rdata[6'(16*0 + csr_raddr[3:0])];
      CSR_PMPADDR16, CSR_PMPADDR17, CSR_PMPADDR18, CSR_PMPADDR19, CSR_PMPADDR20, CSR_PMPADDR21, CSR_PMPADDR22, CSR_PMPADDR23,
      CSR_PMPADDR24, CSR_PMPADDR25, CSR_PMPADDR26, CSR_PMPADDR27, CSR_PMPADDR28, CSR_PMPADDR29, CSR_PMPADDR30, CSR_PMPADDR31:
        csr_rdata_int = pmp_addr_rdata[6'(16*1 + csr_raddr[3:0])];
      CSR_PMPADDR32, CSR_PMPADDR33, CSR_PMPADDR34, CSR_PMPADDR35, CSR_PMPADDR36, CSR_PMPADDR37, CSR_PMPADDR38, CSR_PMPADDR39,
      CSR_PMPADDR40, CSR_PMPADDR41, CSR_PMPADDR42, CSR_PMPADDR43, CSR_PMPADDR44, CSR_PMPADDR45, CSR_PMPADDR46, CSR_PMPADDR47:
        csr_rdata_int = pmp_addr_rdata[6'(16*2 + csr_raddr[3:0])];
      CSR_PMPADDR48, CSR_PMPADDR49, CSR_PMPADDR50, CSR_PMPADDR51, CSR_PMPADDR52, CSR_PMPADDR53, CSR_PMPADDR54, CSR_PMPADDR55,
      CSR_PMPADDR56, CSR_PMPADDR57, CSR_PMPADDR58, CSR_PMPADDR59, CSR_PMPADDR60, CSR_PMPADDR61, CSR_PMPADDR62, CSR_PMPADDR63:
        csr_rdata_int = pmp_addr_rdata[6'(16*3 + csr_raddr[3:0])];

      CSR_MSECCFG:
        csr_rdata_int = pmp_mseccfg_q;

      CSR_MSECCFGH:
        csr_rdata_int = '0;

      CSR_MENVCFG:
        csr_rdata_int = '0;

      CSR_MENVCFGH:
        csr_rdata_int = '0;

      CSR_CPUCTRL, CSR_SECURESEED0, CSR_SECURESEED1, CSR_SECURESEED2: begin
        if (SECURE) begin
          csr_rdata_int = '0; // Read as 0
        end
        else begin
          // Cause illegal CSR access
          csr_rdata_int    = '0;
          illegal_csr_read = 1'b1;
        end
      end

      default: begin
        csr_rdata_int    = '0;
        illegal_csr_read = 1'b1;
      end
    endcase
  end


  // write logic
  always_comb
  begin

    jvt_n                    = '0;
    jvt_we                   = 1'b0;

    mscratch_n               = csr_wdata_int;
    mscratch_we              = 1'b0;
    mepc_n                   = csr_wdata_int & CSR_MEPC_MASK;
    mepc_we                  = 1'b0;
    dpc_n                    = csr_wdata_int & ~32'b1;
    dpc_we                   = 1'b0;

    dcsr_n                   = '{
                                xdebugver : dcsr_q.xdebugver,
                                ebreakm   : csr_wdata_int[15],
                                stepie    : csr_wdata_int[11],
                                step      : csr_wdata_int[2],
                                prv       : PRIV_LVL_M,
                                cause     : dcsr_q.cause,
                                default   : 'd0
                             };
    dcsr_we                  = 1'b0;

    dscratch0_n              = csr_wdata_int;
    dscratch0_we             = 1'b0;
    dscratch1_n              = csr_wdata_int;
    dscratch1_we             = 1'b0;

    // TODO: add support for SD/XS/FS/VS
    mstatus_n                = '{
                              tw:   csr_wdata_int[MSTATUS_TW_BIT],
                              mprv: csr_wdata_int[MSTATUS_MPRV_BIT],
                              mpp:  csr_wdata_int[MSTATUS_MPP_BIT_HIGH:MSTATUS_MPP_BIT_LOW],
                              mpie: csr_wdata_int[MSTATUS_MPIE_BIT],
                              mie:  csr_wdata_int[MSTATUS_MIE_BIT],
                              default: 'b0
                            };

    mstatus_we               = 1'b0;

    // mstatus.mpp is WARL, make sure only legal values are written
    if ((mstatus_n.mpp != PRIV_LVL_M) && (mstatus_n.mpp != PRIV_LVL_U)) begin
      mstatus_n.mpp = PRIV_LVL_M;
    end

    priv_lvl_n      = priv_lvl_q;
    priv_lvl_we     = 1'b0;

    mtvec_n.addr             = csr_mtvec_init_i ? mtvec_addr_i[31:7] : csr_wdata_int[31:7];
    mtvec_n.zero0            = mtvec_q.zero0;
    mtvec_we                 = csr_mtvec_init_i;

    mcounteren_n    = csr_wdata_int;
    mcounteren_we   = 1'b0;

    if (SMCLIC) begin
      mtvec_n.mode             = mtvec_q.mode; // mode is WARL 0x3 when using CLIC

      mtvt_n                   = {csr_wdata_int[31:(32-MTVT_ADDR_WIDTH)], {(32-MTVT_ADDR_WIDTH){1'b0}}};
      mtvt_we                  = 1'b0;

      mnxti_we                 = 1'b0;

      mintstatus_n             = mintstatus_q; // All fields of mintstatus are read only
      mintstatus_we            = 1'b0;

      mintthresh_n             = {24'h000000, csr_wdata_int[7:0]};
      mintthresh_we            = 1'b0;

      mscratchcsw_n            = csr_wdata_int;
      mscratchcsw_we           = 1'b0;

      mscratchcswl_n           = csr_wdata_int;
      mscratchcswl_we          = 1'b0;

      mie_n                    = '0;
      mie_we                   = 1'b0;

      mclicbase_n              = '0; // Read only, tieing to zero for now.
      mclicbase_we             = 1'b0;

      mcause_n                 = '{
                                    irq:            csr_wdata_int[31],
                                    minhv:          csr_wdata_int[30],
                                    mpil:           csr_wdata_int[23:16],
                                    exception_code: csr_wdata_int[10:0],
                                    default:        'b0
                                  };
      mcause_we                = 1'b0;
    end else begin // !SMCLIC
      mtvec_n.mode             = csr_mtvec_init_i ? mtvec_q.mode : {1'b0, csr_wdata_int[0]};

      mtvt_n                   = '0;
      mtvt_we                  = 1'b0;

      mnxti_we                 = 1'b0;

      mintstatus_n             = '0;
      mintstatus_we            = 1'b0;

      mintthresh_n             = '0;
      mintthresh_we            = 1'b0;

      mscratchcsw_n            = '0;
      mscratchcsw_we           = 1'b0;

      mscratchcswl_n           = '0;
      mscratchcswl_we          = 1'b0;

      mie_n                    = csr_wdata_int & IRQ_MASK;
      mie_we                   = 1'b0;

      mclicbase_n              = '0;
      mclicbase_we             = 1'b0;

      mcause_n                 = '{
                                    irq:            csr_wdata_int[31],
                                    exception_code: csr_wdata_int[10:0],
                                    default:        'b0
                                  };
      mcause_we                = 1'b0;
    end

    pmpncfg_we_int  = {PMP_MAX_REGIONS{1'b0}};
    pmp_addr_n      = csr_wdata_int[31-:PMP_ADDR_WIDTH];
    pmp_addr_we_int = {PMP_MAX_REGIONS{1'b0}};
    pmp_mseccfg_we  = 1'b0;

    cpuctrl_n       = csr_wdata_int & CSR_CPUCTRL_MASK;
    cpuctrl_we      = 1'b0;
    secureseed0_n   = csr_wdata_int;
    secureseed0_we  = 1'b0;
    secureseed1_n   = csr_wdata_int;
    secureseed1_we  = 1'b0;
    secureseed2_n   = csr_wdata_int;
    secureseed2_we  = 1'b0;

    if (csr_we_int) begin
      case (csr_waddr)
        // jvt: Jump vector table
        CSR_JVT: begin
          if (ZC_EXT) begin
          jvt_we = 1'b1;
        end
        end
        // mstatus: IE bit
        CSR_MSTATUS: begin
          mstatus_we = 1'b1;
        end
        CSR_MSTATUSH: begin
          // No bits implemented in MSTATUSH, do nothing
        end
        // mie: machine interrupt enable
        CSR_MIE: begin
          // CLIC mode is assumed when SMCLIC = 1
          if (!SMCLIC) begin
            mie_we = 1'b1;
          end
        end
        // mtvec: machine trap-handler base address
        CSR_MTVEC: begin
              mtvec_we = 1'b1;
        end
        // mcounteren: counter enable
        CSR_MCOUNTEREN: begin
              mcounteren_we = 1'b1;
        end
        // mtvt: machine trap-handler vector table base address
        CSR_MTVT: begin
          if (SMCLIC) begin
            mtvt_we = 1'b1;
          end
        end
        // mscratch: machine scratch
        CSR_MSCRATCH: begin
              mscratch_we = 1'b1;
        end
        // mepc: exception program counter
        CSR_MEPC: begin
              mepc_we = 1'b1;
        end
        // mcause
        CSR_MCAUSE: begin
            mcause_we = 1'b1;
            // CLIC mode is assumed when SMCLIC = 1
            // For CLIC, a write to mcause.mpp or mcause.mpie will write to the
            // corresponding bits in mstatus as well.
            if (SMCLIC) begin
              mstatus_we = 1'b1;
            end
        end
        CSR_MNXTI: begin
          if (SMCLIC) begin
            mnxti_we = 1'b1;

            // Writes to mnxti also writes to mstatus
            mstatus_we = 1'b1;

            // Writes to mintstatus.mil and mcause depend on the current state of
            // clic interrupts AND the type of CSR instruction used.
            // Side effects occur when there is an actual write to the mstatus CSR
            // This is already coded into the csr_we_int/mnxti_we
            if (mnxti_irq_pending_i) begin
              mintstatus_we = 1'b1;
              mcause_we     = 1'b1;
            end
          end
        end
        CSR_MINTSTATUS: begin
          if (SMCLIC) begin
            mintstatus_we = 1'b1;
          end
        end
        CSR_MINTTHRESH: begin
          if (SMCLIC) begin
            mintthresh_we = 1'b1;
          end
        end
        CSR_MSCRATCHCSW: begin
          if (SMCLIC) begin
            mscratchcsw_we = 1'b1;
          end
        end
        CSR_MSCRATCHCSWL: begin
          if (SMCLIC) begin
            mscratchcswl_we = 1'b1;
          end
        end
        CSR_MCLICBASE: begin
          if (SMCLIC) begin
            mclicbase_we = 1'b1;
          end
        end
        CSR_DCSR: begin
              dcsr_we = 1'b1;
        end
        CSR_DPC: begin
                dpc_we = 1'b1;
        end
        CSR_DSCRATCH0: begin
                dscratch0_we = 1'b1;
        end
        CSR_DSCRATCH1: begin
                dscratch1_we = 1'b1;
        end
        CSR_PMPCFG0,  CSR_PMPCFG1,  CSR_PMPCFG2,  CSR_PMPCFG3,
        CSR_PMPCFG4,  CSR_PMPCFG5,  CSR_PMPCFG6,  CSR_PMPCFG7,
        CSR_PMPCFG8,  CSR_PMPCFG9,  CSR_PMPCFG10, CSR_PMPCFG11,
        CSR_PMPCFG12, CSR_PMPCFG13, CSR_PMPCFG14, CSR_PMPCFG15: begin
          pmpncfg_we_int[csr_waddr[3:0]*4+:4] = 4'hF;
        end
        CSR_PMPADDR0,  CSR_PMPADDR1,  CSR_PMPADDR2,  CSR_PMPADDR3,
        CSR_PMPADDR4,  CSR_PMPADDR5,  CSR_PMPADDR6,  CSR_PMPADDR7,
        CSR_PMPADDR8,  CSR_PMPADDR9,  CSR_PMPADDR10, CSR_PMPADDR11,
        CSR_PMPADDR12, CSR_PMPADDR13, CSR_PMPADDR14, CSR_PMPADDR15: begin
          pmp_addr_we_int[6'(16*0 + csr_waddr[3:0])] = 1'b1;
        end
        CSR_PMPADDR16, CSR_PMPADDR17, CSR_PMPADDR18, CSR_PMPADDR19,
        CSR_PMPADDR20, CSR_PMPADDR21, CSR_PMPADDR22, CSR_PMPADDR23,
        CSR_PMPADDR24, CSR_PMPADDR25, CSR_PMPADDR26, CSR_PMPADDR27,
        CSR_PMPADDR28, CSR_PMPADDR29, CSR_PMPADDR30, CSR_PMPADDR31: begin
          pmp_addr_we_int[6'(16*1 + csr_waddr[3:0])] = 1'b1;
        end
        CSR_PMPADDR32, CSR_PMPADDR33, CSR_PMPADDR34, CSR_PMPADDR35,
        CSR_PMPADDR36, CSR_PMPADDR37, CSR_PMPADDR38, CSR_PMPADDR39,
        CSR_PMPADDR40, CSR_PMPADDR41, CSR_PMPADDR42, CSR_PMPADDR43,
        CSR_PMPADDR44, CSR_PMPADDR45, CSR_PMPADDR46, CSR_PMPADDR47: begin
          pmp_addr_we_int[6'(16*2 + csr_waddr[3:0])] = 1'b1;
        end
        CSR_PMPADDR48, CSR_PMPADDR49, CSR_PMPADDR50, CSR_PMPADDR51,
        CSR_PMPADDR52, CSR_PMPADDR53, CSR_PMPADDR54, CSR_PMPADDR55,
        CSR_PMPADDR56, CSR_PMPADDR57, CSR_PMPADDR58, CSR_PMPADDR59,
        CSR_PMPADDR60, CSR_PMPADDR61, CSR_PMPADDR62, CSR_PMPADDR63: begin
          pmp_addr_we_int[6'(16*3 + csr_waddr[3:0])] = 1'b1;
        end
        CSR_MSECCFG: begin
          pmp_mseccfg_we = 1'b1;
        end
        CSR_MSECCFGH: begin
          // No bits implemented in MSECCFGH, do nothing
        end
        CSR_MENVCFG: begin
          // No bits implemented in MENVCFG, do nothing
        end
        CSR_MENVCFGH: begin
          // No bits implemented in MENVCFGH, do nothing
        end
        CSR_CPUCTRL: begin
          if (SECURE) begin
            cpuctrl_we = 1'b1;
          end
        end
        CSR_SECURESEED0: begin
          if (SECURE) begin
            secureseed0_we = 1'b1;
          end
        end
        CSR_SECURESEED1: begin
          if (SECURE) begin
            secureseed1_we = 1'b1;
          end
        end
        CSR_SECURESEED2: begin
          if (SECURE) begin
            secureseed2_we = 1'b1;
          end
        end
      endcase
    end

    // CSR side effects from other CSRs
    // All write enables are already calculated at this point

    // CLIC mode is assumed when SMCLIC = 1
    if (SMCLIC) begin
      if (mnxti_we) begin
        // mintstatus and mcause are updated if an actual mstatus write happens and
        // a higher level non-shv interrupt is pending.
        // This is already decoded into the respective _we signals below.
        if (mintstatus_we) begin
          mintstatus_n.mil = mnxti_irq_level_i;
        end
        if (mcause_we) begin
          mcause_n = mcause_q;
          mcause_n.irq = 1'b1;
          mcause_n.exception_code = {1'b0, 10'(mnxti_irq_id_i)};
        end
      end else if (mcause_we) begin
        // In CLIC mode, writes to mcause.mpp/mpie is aliased to mstatus.mpp/mpie
        // All other mstatus bits are preserved
        mstatus_n      = mstatus_q; // Preserve all fields

        // Write mpie and mpp as aliased through mcause
        mstatus_n.mpie = csr_wdata_int[MCAUSE_MPIE_BIT];
        mstatus_n.mpp  = csr_wdata_int[MSTATUS_MPP_BIT_HIGH:MSTATUS_MPP_BIT_LOW];

        // mstatus.mpp is WARL, make sure only legal values are written
        if ((mstatus_n.mpp != PRIV_LVL_M) && (mstatus_n.mpp != PRIV_LVL_U)) begin
          mstatus_n.mpp = PRIV_LVL_M;
        end
      end
      // The CLIC pointer address should always be output for an access to MNXTI,
      // but will only contain a nonzero value if a CLIC interrupt is actually pending
      // with a higher level. The valid below will be high also for the cases where
      // no side effects occur.
      clic_pa_valid_o = csr_en_gated && (csr_waddr == CSR_MNXTI);
      clic_pa_o       = mnxti_irq_pending_i ? {mtvt_addr_o, mnxti_irq_id_i, 2'b00} : 32'h00000000;
    end else begin
      clic_pa_valid_o = 1'b0;
      clic_pa_o       = '0;
    end



    // exception controller gets priority over other writes
    unique case (1'b1)

      ctrl_fsm_i.csr_save_cause: begin

        if (ctrl_fsm_i.debug_csr_save) begin
            // all interrupts are masked, don't update cause, epc, tval dpc and
            // mpstatus
            // dcsr.nmip is not a flop, but comes directly from the controller
            dcsr_n = '{
              xdebugver : dcsr_q.xdebugver,
              ebreakm   : dcsr_q.ebreakm,
              stepie    : dcsr_q.stepie,
              step      : dcsr_q.step,
              prv       : PRIV_LVL_M,
              cause     : ctrl_fsm_i.debug_cause,
              default   : 'd0
            };
            dcsr_we = 1'b1;

            dpc_n  = ctrl_fsm_i.pipe_pc;
            dpc_we = 1'b1;
        end else begin
          priv_lvl_n     = PRIV_LVL_M; // trap into machine mode
          priv_lvl_we    = 1'b1;

          mstatus_n      = mstatus_q;
          mstatus_n.mie  = 1'b0;
          mstatus_n.mpie = mstatus_q.mie;
          mstatus_n.mpp  = priv_lvl_q;
          mstatus_we     = 1'b1;

          mepc_n         = ctrl_fsm_i.pipe_pc;
          mepc_we        = 1'b1;

          mcause_n       = ctrl_fsm_i.csr_cause;

          if (SMCLIC) begin
            // mpil is saved from mintstatus
            mcause_n.mpil = mintstatus_q.mil;

            // todo: handle exception vs interrupt
            // Save new interrupt level to mintstatus
            mintstatus_n.mil = ctrl_fsm_i.irq_level;
            mintstatus_we = 1'b1;
          end else begin
            mcause_n.mpil = '0;
          end

          mcause_we = 1'b1;

        end
      end //ctrl_fsm_i.csr_save_cause
      ctrl_fsm_i.csr_restore_mret: begin //MRET
        priv_lvl_n     = privlvl_t'(mstatus_q.mpp);
        priv_lvl_we    = 1'b1;
        mstatus_n      = mstatus_q;
        mstatus_n.mie  = mstatus_q.mpie;
        mstatus_n.mpie = 1'b1;
        mstatus_n.mpp  = PRIV_LVL_U;
        mstatus_n.mprv = (privlvl_t'(mstatus_q.mpp) == PRIV_LVL_M) ? mstatus_q.mprv : 1'b0;
        mstatus_we = 1'b1;

        if (SMCLIC) begin
          mintstatus_n.mil = mcause_q.mpil;
          mintstatus_we = 1'b1;
        end
      end //ctrl_fsm_i.csr_restore_mret
      ctrl_fsm_i.csr_restore_dret: begin //DRET
          // Restore to the recorded privilege level
          priv_lvl_n = dcsr_q.prv;
      end //ctrl_fsm_i.csr_restore_dret

      // mcause.minhv shall be cleared if vector fetch is successful
      ctrl_fsm_i.csr_clear_minhv: begin
        if (SMCLIC) begin
          mcause_n = mcause_q;
          mcause_n.minhv = 1'b0;
          mcause_we = 1'b1;
        end
      end

      default:;
    endcase
  end


  // CSR operation logic
  // Using ex_wb_pipe_i.rf_wdata for read-modify-write since CSR was read in EX, written in WB
  always_comb
  begin
    if(!csr_en_gated) begin
      csr_wdata_int = csr_wdata;
      csr_we_int    = 1'b0;
    end else begin
      csr_we_int    = 1'b1;
      case (csr_op)
        CSR_OP_WRITE: csr_wdata_int = csr_wdata;
        CSR_OP_SET:   csr_wdata_int = csr_wdata | ex_wb_pipe_i.rf_wdata;
        CSR_OP_CLEAR: csr_wdata_int = (~csr_wdata) & ex_wb_pipe_i.rf_wdata;

        CSR_OP_READ: begin
          csr_wdata_int = csr_wdata;
          csr_we_int    = 1'b0;
        end
      endcase
    end
  end

  cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      (32),
    .MASK       (CSR_JVT_MASK),
    .SHADOWCOPY (SECURE),
    .RESETVALUE (32'd0)
  ) jvt_csr_i (
    .clk        (clk),
    .rst_n      (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (jvt_n),
    .wr_en_i    (jvt_we),
    .rd_data_o  (jvt_q),
    .rd_error_o (jvt_rd_error)
  );

  cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      (32),
    .SHADOWCOPY (1'b0),
    .RESETVALUE (32'd0)
  ) dscratch0_csr_i (
    .clk      (clk),
    .rst_n     (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (dscratch0_n),
    .wr_en_i    (dscratch0_we),
    .rd_data_o  (dscratch0_q),
    .rd_error_o (dscratch0_rd_error)
  );

  cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      (32),
    .SHADOWCOPY (1'b0),
    .RESETVALUE (32'd0)
  ) dscratch1_csr_i (
    .clk      (clk),
    .rst_n     (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (dscratch1_n),
    .wr_en_i    (dscratch1_we),
    .rd_data_o  (dscratch1_q),
    .rd_error_o (dscratch1_rd_error)
  );

 cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      (32),
    .MASK       (CSR_DCSR_MASK),
    .SHADOWCOPY (SECURE),
    .RESETVALUE (DCSR_RESET_VAL)
  ) dcsr_csr_i (
    .clk      (clk),
    .rst_n     (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (dcsr_n),
    .wr_en_i    (dcsr_we),
    .rd_data_o  (dcsr_q),
    .rd_error_o (dcsr_rd_error)
  );

  cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      (32),
    .SHADOWCOPY (1'b0),
    .RESETVALUE (32'd0)
  ) dpc_csr_i (
    .clk      (clk),
    .rst_n     (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (dpc_n),
    .wr_en_i    (dpc_we),
    .rd_data_o  (dpc_q),
    .rd_error_o (dpc_rd_error)
  );

  cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      (32),
    .MASK       (CSR_MEPC_MASK),
    .SHADOWCOPY (SECURE),
    .RESETVALUE (32'd0)
  ) mepc_csr_i (
    .clk      (clk),
    .rst_n     (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (mepc_n),
    .wr_en_i    (mepc_we),
    .rd_data_o  (mepc_q),
    .rd_error_o (mepc_rd_error)
  );

  cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      (32),
    .MASK       (CSR_MSCRATCH_MASK),
    .SHADOWCOPY (SECURE),
    .RESETVALUE (32'd0)
  ) mscratch_csr_i (
    .clk      (clk),
    .rst_n     (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (mscratch_n),
    .wr_en_i    (mscratch_we),
    .rd_data_o  (mscratch_q),
    .rd_error_o (mscratch_rd_error)
  );

  cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      (32),
    .MASK       (CSR_MSTATUS_MASK),
    .SHADOWCOPY (SECURE),
    .RESETVALUE (MSTATUS_RESET_VAL)
  ) mstatus_csr_i (
    .clk      (clk),
    .rst_n     (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (mstatus_n),
    .wr_en_i    (mstatus_we),
    .rd_data_o  (mstatus_q),
    .rd_error_o (mstatus_rd_error)
  );

  cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      (32),
    .SHADOWCOPY (1'b0),
    .RESETVALUE (32'd0)
  ) mcause_csr_i (
    .clk      (clk),
    .rst_n     (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (mcause_n),
    .wr_en_i    (mcause_we),
    .rd_data_o  (mcause_q),
    .rd_error_o (mcause_rd_error)
  );

  assign mcause_o = mcause_q;



  generate
    if (SMCLIC) begin : smclic_regs

      cv32e40s_csr #(
        .LIB        (LIB),
        .WIDTH      (32),
        .SHADOWCOPY (1'b0),
        .RESETVALUE (MTVEC_CLIC_RESET_VAL)
      ) mtvec_csr_i (
        .clk      (clk),
        .rst_n     (rst_n),
        .scan_cg_en_i (scan_cg_en_i),
        .wr_data_i  (mtvec_n),
        .wr_en_i    (mtvec_we),
        .rd_data_o  (mtvec_q),
        .rd_error_o (mtvec_rd_error)
      );
      cv32e40s_csr #(
        .LIB        (LIB),
        .WIDTH      (32),
        .MASK       (CSR_MTVT_MASK),
        .SHADOWCOPY (SECURE),
        .RESETVALUE (MTVT_RESET_VAL)
      ) mtvt_csr_i (
        .clk        (clk),
        .rst_n      (rst_n),
        .scan_cg_en_i (scan_cg_en_i),
        .wr_data_i  (mtvt_n),
        .wr_en_i    (mtvt_we),
        .rd_data_o  (mtvt_q),
        .rd_error_o (mtvt_rd_error)
      );

      assign mtvt_addr_o = mtvt_q.addr[31:(32-MTVT_ADDR_WIDTH)];

      cv32e40s_csr #(
        .LIB        (LIB),
        .WIDTH      (32),
        .MASK       (CSR_MINTSTATUS_MASK),
        .SHADOWCOPY (SECURE),
        .RESETVALUE (MINTSTATUS_RESET_VAL)
      ) mintstatus_csr_i (
        .clk        (clk),
        .rst_n      (rst_n),
        .scan_cg_en_i (scan_cg_en_i),
        .wr_data_i  (mintstatus_n),
        .wr_en_i    (mintstatus_we),
        .rd_data_o  (mintstatus_q),
        .rd_error_o (mintstatus_rd_error)
      );
      cv32e40s_csr #(
        .LIB        (LIB),
        .WIDTH      (32),
        .MASK       (CSR_MINTTHRESH_MASK),
        .SHADOWCOPY (SECURE),
        .RESETVALUE (32'h0)
      ) mintthresh_csr_i (
        .clk        (clk),
        .rst_n      (rst_n),
        .scan_cg_en_i (scan_cg_en_i),
        .wr_data_i  (mintthresh_n),
        .wr_en_i    (mintthresh_we),
        .rd_data_o  (mintthresh_q),
        .rd_error_o (mintthresh_rd_error)
      );
      cv32e40s_csr #(
        .LIB        (LIB),
        .WIDTH      (32),
        .MASK       (CSR_MSCRATCHCSW_MASK),
        .SHADOWCOPY (SECURE),
        .RESETVALUE (32'h0)
      ) mscratchcsw_csr_i (
        .clk        (clk),
        .rst_n      (rst_n),
        .scan_cg_en_i (scan_cg_en_i),
        .wr_data_i  (mscratchcsw_n),
        .wr_en_i    (mscratchcsw_we),
        .rd_data_o  (mscratchcsw_q),
        .rd_error_o (mscratchcsw_rd_error)
      );
      cv32e40s_csr #(
        .LIB        (LIB),
        .WIDTH      (32),
        .MASK       (CSR_MSCRATCHCSWL_MASK),
        .SHADOWCOPY (SECURE),
        .RESETVALUE (32'h0)
      ) mscratchcswl_csr_i (
        .clk        (clk),
        .rst_n      (rst_n),
        .scan_cg_en_i (scan_cg_en_i),
        .wr_data_i  (mscratchcswl_n),
        .wr_en_i    (mscratchcswl_we),
        .rd_data_o  (mscratchcswl_q),
        .rd_error_o (mscratchcswl_rd_error)
      );
      cv32e40s_csr #(
        .LIB        (LIB),
        .WIDTH      (32),
        .MASK       (CSR_MCLICBASE_MASK),
        .SHADOWCOPY (SECURE),
        .RESETVALUE (32'h0)
      ) mclicbase_csr_i (
        .clk        (clk),
        .rst_n      (rst_n),
        .scan_cg_en_i (scan_cg_en_i),
        .wr_data_i  (mclicbase_n),
        .wr_en_i    (mclicbase_we),
        .rd_data_o  (mclicbase_q),
        .rd_error_o (mclicbase_rd_error)
      );

      assign mie_q        = 32'h0;
      assign mie_rd_error = 1'b0;

    end else begin : basic_mode_regs
      cv32e40s_csr #(
        .WIDTH      (32),
        .SHADOWCOPY (1'b0),
        .RESETVALUE (MTVEC_BASIC_RESET_VAL)
      ) mtvec_csr_i (
        .clk      (clk),
        .rst_n     (rst_n),
        .scan_cg_en_i (scan_cg_en_i),
        .wr_data_i  (mtvec_n),
        .wr_en_i    (mtvec_we),
        .rd_data_o  (mtvec_q),
        .rd_error_o (mtvec_rd_error)
      );
      // Only include mie CSR when SMCLIC = 0
      cv32e40s_csr #(
        .LIB        (LIB),
        .WIDTH      (32),
        .MASK       (IRQ_MASK),
        .SHADOWCOPY (SECURE),
        .RESETVALUE (32'd0)
      ) mie_csr_i (
        .clk      (clk),
        .rst_n     (rst_n),
        .scan_cg_en_i (scan_cg_en_i),
        .wr_data_i  (mie_n),
        .wr_en_i    (mie_we),
        .rd_data_o  (mie_q),
        .rd_error_o (mie_rd_error)
      );

      assign mtvt_q              = 32'h0;
      assign mtvt_rd_error       = 1'b0;
      assign mintstatus_q        = 32'h0;
      assign mintstatus_rd_error = 1'b0;
      assign mintthresh_q        = 32'h0;
      assign mintthresh_rd_error = 1'b0;
      assign mscratchcsw_q       = 32'h0;
      assign mscratchcswl_q      = 32'h0;
      assign mclicbase_q         = 32'h0;
    end

    if (SECURE) begin : xsecure

      logic [2:0] lfsr_lockup;

      cv32e40s_csr #(
        .LIB        (LIB),
        .WIDTH      (32),
        .MASK       (CSR_CPUCTRL_MASK),
        .SHADOWCOPY (SECURE),
        .RESETVALUE (32'd0)
        ) cpuctrl_csr_i (
          .clk        (clk),
          .rst_n      (rst_n),
          .scan_cg_en_i (scan_cg_en_i),
          .wr_data_i  (cpuctrl_n),
          .wr_en_i    (cpuctrl_we),
          .rd_data_o  (cpuctrl_q),
          .rd_error_o (cpuctrl_rd_error)
        );

      // Shifting LFSR0 in IF because it controls instruction insertion
      cv32e40s_lfsr #(
        .LFSR_CFG     (LFSR0_CFG)
        ) lfsr0_i (
          .clk        (clk),
          .rst_n      (rst_n),
          .seed_i     (secureseed0_n),
          .seed_we_i  (secureseed0_we),
          .enable_i   (cpuctrl_q.rnddummy),
          .shift_i    (lfsr_shift_if_i),
          .data_o     (xsecure_ctrl_o.lfsr0),
          .lockup_o   (lfsr_lockup[0])
        );

      // Shifting lfsr 1 and 2 in ID because they control the operand values
      cv32e40s_lfsr #(
        .LFSR_CFG     (LFSR1_CFG)
        ) lfsr1_i (
          .clk        (clk),
          .rst_n      (rst_n),
          .seed_i     (secureseed1_n),
          .seed_we_i  (secureseed1_we),
          .enable_i   (cpuctrl_q.rnddummy),
          .shift_i    (lfsr_shift_id_i),
          .data_o     (xsecure_ctrl_o.lfsr1),
          .lockup_o   (lfsr_lockup[1])
        );

      cv32e40s_lfsr #(
        .LFSR_CFG     (LFSR2_CFG)
        ) lfsr2_i (
          .clk        (clk),
          .rst_n      (rst_n),
          .seed_i     (secureseed2_n),
          .seed_we_i  (secureseed2_we),
          .enable_i   (cpuctrl_q.rnddummy),
          .shift_i    (lfsr_shift_id_i),
          .data_o     (xsecure_ctrl_o.lfsr2),
          .lockup_o   (lfsr_lockup[2])
        );

      // Populate xsecure_ctrl
      assign xsecure_ctrl_o.cpuctrl = cpuctrl_t'(cpuctrl_q);

      // Combine lockup singals for alert
      assign lfsr_lockup_o = |lfsr_lockup;

      // Reset dummy instruction counter when writing registers that affect insertion frequency
      assign xsecure_ctrl_o.cntrst = cpuctrl_we || secureseed0_we || lfsr_lockup[0];

    end // block: xsecure
    else begin : no_xsecure

      // Tie off
      assign xsecure_ctrl_o.cpuctrl = cpuctrl_t'('0);
      assign xsecure_ctrl_o.lfsr0   = '0;
      assign xsecure_ctrl_o.lfsr1   = '0;
      assign xsecure_ctrl_o.lfsr2   = '0;
      assign cpuctrl_rd_error       = 1'b0;
      assign lfsr_lockup_o          = 1'b0;

    end
  endgenerate


  assign csr_wr_in_wb = ex_wb_pipe_i.csr_en &&
                        ex_wb_pipe_i.instr_valid &&
                        ((csr_op == CSR_OP_WRITE) ||
                         (csr_op == CSR_OP_SET)   ||
                         (csr_op == CSR_OP_CLEAR));

  // xsecure CSRs has impact on pipeline operation. When updated, clear pipeline.
  // div/divu/rem/remu and branch decisions in EX stage depend on cpuctrl.dataindtiming
  // Dummy instruction insertion depend on cpuctrl.dummyen/dummyfreq
  assign xsecure_csr_wr_in_wb   = SECURE &&
                                  csr_wr_in_wb &&
                                  ((csr_waddr == CSR_CPUCTRL)     ||
                                   (csr_waddr == CSR_SECURESEED0) ||
                                   (csr_waddr == CSR_SECURESEED1) ||
                                   (csr_waddr == CSR_SECURESEED2));

  // PMP CSRs affect memory access permissions. When updated, the pipeline must be flushed
  // to ensure succseeding instructions are executed with correct permissions
  assign pmp_csr_wr_in_wb = csr_wr_in_wb &&
                            (|pmpncfg_wr_addr_match ||
                             |pmpaddr_wr_addr_match ||
                             (csr_waddr == CSR_MSECCFG));


  assign csr_wr_in_wb_flush_o = xsecure_csr_wr_in_wb || pmp_csr_wr_in_wb;

  assign csr_rdata_o = csr_rdata_int;

  // Privledge level register
  cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      ($bits(privlvl_t)),
    .SHADOWCOPY (1'b0),
    .RESETVALUE (PRIV_LVL_M)
  ) priv_lvl_i (
    .clk      (clk),
    .rst_n     (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (priv_lvl_n),
    .wr_en_i    (priv_lvl_we),
    .rd_data_o  (priv_lvl_q_int),
    .rd_error_o (priv_lvl_error)
  );

  assign priv_lvl_q = privlvl_t'(priv_lvl_q_int);

  // Generate priviledge level for the IF stage
  // Since MRET may change the priviledge level and can is taken from ID,
  // the priviledge level for the IF stage needs to be predictive
  always_comb begin
    priv_lvl_if_ctrl_o.priv_lvl     = priv_lvl_q;
    priv_lvl_if_ctrl_o.priv_lvl_set = 1'b0;

    if (priv_lvl_we) begin
      // Priviledge level updated by MRET in WB or exception
      priv_lvl_if_ctrl_o.priv_lvl     = priv_lvl_n;
      priv_lvl_if_ctrl_o.priv_lvl_set = 1'b1;
    end
    else if (ctrl_fsm_i.mret_jump_id) begin
      // MRET in ID. Set IF stage priviledge level to mstatus.mpp
      // Using mstatus_q.mpp is safe since a write to mstatus.mpp in EX or WB it will cause a stall
      priv_lvl_if_ctrl_o.priv_lvl     = privlvl_t'(mstatus_q.mpp);
      priv_lvl_if_ctrl_o.priv_lvl_set = 1'b1;
    end
    else if ((id_ex_pipe_i.sys_en && id_ex_pipe_i.sys_mret_insn && ctrl_fsm_i.kill_ex) ||
             (ex_wb_pipe_i.sys_en && ex_wb_pipe_i.sys_mret_insn && ctrl_fsm_i.kill_wb) ||
             (sys_en_id_i && sys_mret_id_i && ctrl_fsm_i.kill_id)) begin
      // MRET got killed before retiring in the WB stage. Restore IF priviledge level
      // In most cases, the logic behind priv_lvl_we and priv_lvl_n will take care of this.
      // The exception is if debug mode is entered after MRET jump from ID is taken, and the MRET is killed.
      // TODO: revisit this when implementing the debug related parts of user mode
      priv_lvl_if_ctrl_o.priv_lvl     = priv_lvl_q;
      priv_lvl_if_ctrl_o.priv_lvl_set = 1'b1;
    end
  end

  // Lookahead for priv_lvl_lsu_o. Updates to MPRV or MPP in WB needs to take effect for load/stores in EX
  always_comb begin
    if (mstatus_we) begin
      priv_lvl_lsu_o = mstatus_n.mprv ? privlvl_t'(mstatus_n.mpp) : id_ex_pipe_i.priv_lvl;
    end
    else begin
      priv_lvl_lsu_o = mstatus_q.mprv ? privlvl_t'(mstatus_q.mpp) : id_ex_pipe_i.priv_lvl;
    end
  end

  // Privilege level for CLIC pointer fetches in IF
  // When an interrupt is taken, the pipeline is killed. The privilege level will be changed, so in case
  // of a privilege level change, we need to use the level in the priv_lvl_if_ctrl_o when mprv is not set.
  // priv_lvl_if_ctrl_o should carry the correct privilege level.
  always_comb begin
    if (mstatus_we) begin
      priv_lvl_clic_ptr_o = mstatus_n.mprv ? privlvl_t'(mstatus_n.mpp) : priv_lvl_if_ctrl_o.priv_lvl;
    end
    else begin
      priv_lvl_clic_ptr_o = mstatus_q.mprv ? privlvl_t'(mstatus_q.mpp) : priv_lvl_if_ctrl_o.priv_lvl;
    end
  end


  // priv_lvl_o indicates the currently active priviledge level (updated when taking an exception, and when MRET is in WB)
  assign priv_lvl_o = priv_lvl_q;

  // Global machine mode interrupt enable
  // Machine mode interrupts are always enabled when in a lower privilege mode
  // When single stepping, interrupt enable is gated by dcsr.stepie
  assign m_irq_enable_o  = (mstatus_q.mie || (priv_lvl_q < PRIV_LVL_M)) &&
                           !(dcsr_q.step && !dcsr_q.stepie);

  // directly output some registers
  assign mstatus_o       = mstatus_q;

  assign mtvec_addr_o    = mtvec_q.addr;
  assign mtvec_mode_o    = mtvec_q.mode;

  assign mepc_o          = mepc_q;
  assign dpc_o           = dpc_q;
  assign dcsr_o          = dcsr_q;

  assign mie_o = mie_q;

  generate
    if(PMP_NUM_REGIONS > 0) begin: csr_pmp
      for(genvar i=0; i < PMP_MAX_REGIONS; i++)  begin: gen_pmp_csr

        if(i < PMP_NUM_REGIONS) begin: pmp_region


          assign pmpncfg_wr_addr_match[i] = (csr_waddr == csr_num_e'(CSR_PMPCFG0 + i));

          // Smepmp spec version 1.0, 4b: When mseccfg.mml==1, M-mode only or locked shared regions with executable privileges is not possible, and such writes are ignored. Exempt when mseccfg.rlb==1
          assign pmpncfg_warl_ignore_wr[i] = pmp_mseccfg_q.rlb ? 1'b0 :
                                             pmp_mseccfg_q.mml &&
                                             (({pmpncfg_n[i].lock, pmpncfg_n[i].read, pmpncfg_n[i].write, pmpncfg_n[i].exec} == 4'b1001) || // Locked region, M-mode: execute,      S/U mode: none
                                              ({pmpncfg_n[i].lock, pmpncfg_n[i].read, pmpncfg_n[i].write, pmpncfg_n[i].exec} == 4'b1010) || // Locked region, M-mode: execute,      S/U mode: execute
                                              ({pmpncfg_n[i].lock, pmpncfg_n[i].read, pmpncfg_n[i].write, pmpncfg_n[i].exec} == 4'b1011) || // Locked region, M-mode: read/execute, S/U mode: execute
                                              ({pmpncfg_n[i].lock, pmpncfg_n[i].read, pmpncfg_n[i].write, pmpncfg_n[i].exec} == 4'b1101));  // Locked region, M-mode: read/execute, S/U mode: none

          // MSECCFG.RLB allows the lock bit to be bypassed
          assign pmpncfg_locked[i] = pmpncfg_q[i].lock && !pmp_mseccfg_q.rlb;

          // Qualify PMPCFG write strobe with lock status
          assign pmpncfg_we[i] = pmpncfg_we_int[i] && !(pmpncfg_locked[i] || pmpncfg_warl_ignore_wr[i]);

          // Extract PMPCFGi bits from wdata
          always_comb begin

            pmpncfg_n[i]       = csr_wdata_int[(i%4)*PMPNCFG_W+:PMPNCFG_W];
            pmpncfg_n[i].zero0 = '0;

            // RW = 01 is a reserved combination, and shall result in RW = 00, unless mseccfg.mml==1
            if (!pmpncfg_n[i].read && pmpncfg_n[i].write && !pmp_mseccfg_q.mml) begin
              pmpncfg_n[i].read  = 1'b0;
              pmpncfg_n[i].write = 1'b0;
            end

            // NA4 mode is not selectable when G > 0, mode is treated as OFF
            unique case (csr_wdata_int[(i%4)*PMPNCFG_W+3+:2])
              PMP_MODE_OFF   : pmpncfg_n[i].mode = PMP_MODE_OFF;
              PMP_MODE_TOR   : pmpncfg_n[i].mode = PMP_MODE_TOR;
              PMP_MODE_NA4   : pmpncfg_n[i].mode = (PMP_GRANULARITY == 0) ? PMP_MODE_NA4 :
                                                    PMP_MODE_OFF;
              PMP_MODE_NAPOT : pmpncfg_n[i].mode = PMP_MODE_NAPOT;
              default : pmpncfg_n[i].mode = PMP_MODE_OFF;
            endcase
          end

          cv32e40s_csr #(
                         .LIB        (LIB),
                         .WIDTH      ($bits(pmpncfg_t)),
                         .MASK       (CSR_PMPNCFG_MASK),
                         .SHADOWCOPY (SECURE),
                         .RESETVALUE (PMP_PMPNCFG_RV[i]))
          pmpncfg_csr_i
            (.clk        (clk),
             .rst_n      (rst_n),
             .scan_cg_en_i (scan_cg_en_i),
             .wr_data_i  (pmpncfg_n[i]),
             .wr_en_i    (pmpncfg_we[i]),
             .rd_data_o  (pmpncfg_q[i]),
             .rd_error_o (pmpncfg_rd_error[i]));

          assign csr_pmp_o.cfg[i] = pmpncfg_q[i];

          if (i == PMP_NUM_REGIONS-1) begin: pmp_addr_qual_upper
            assign pmp_addr_we[i] = pmp_addr_we_int[i] &&
                                    !pmpncfg_locked[i];
          end
          else begin: pmp_addr_qual_other
            // If the region at the next index is configured as TOR, this region's address register is locked
            assign pmp_addr_we[i] = pmp_addr_we_int[i] &&
                                    !pmpncfg_locked[i] &&
                                    (!pmpncfg_locked[i+1] || pmpncfg_q[i+1].mode != PMP_MODE_TOR);
          end

          assign pmpaddr_wr_addr_match[i] = (csr_waddr == csr_num_e'(CSR_PMPADDR0 + i));

          cv32e40s_csr #(
                         .LIB        (LIB),
                         .WIDTH      (PMP_ADDR_WIDTH),
                         .MASK       (CSR_PMPADDR_MASK),
                         .SHADOWCOPY (SECURE),
                         .RESETVALUE (PMP_PMPADDR_RV[i][31-:PMP_ADDR_WIDTH]))
          pmp_addr_csr_i
            (.clk        (clk),
             .rst_n      (rst_n),
             .scan_cg_en_i (scan_cg_en_i),
             .wr_data_i  (pmp_addr_n),
             .wr_en_i    (pmp_addr_we[i]),
             .rd_data_o  (pmp_addr_q[i]),
             .rd_error_o (pmp_addr_rd_error[i]));


          if (PMP_GRANULARITY == 0) begin: pmp_addr_rdata_g0
            // If G == 0, read data is unmodified
            assign pmp_addr_rdata[i] = pmp_addr_q[i];
          end
          else if (PMP_GRANULARITY == 1) begin: pmp_addr_rdata_g1
            // If G == 1, bit [G-1] reads as zero in TOR or OFF mode
            always_comb begin
              pmp_addr_rdata[i] = pmp_addr_q[i];
              if ((pmpncfg_q[i].mode == PMP_MODE_OFF) ||
                  (pmpncfg_q[i].mode == PMP_MODE_TOR)) begin
                pmp_addr_rdata[i][PMP_GRANULARITY-1:0] = '0;
              end
            end
          end
          else begin: pmp_addr_rdata_g2
            // For G >= 2, bits are masked to one or zero depending on the mode
            always_comb begin
              // In NAPOT mode, bits [G-2:0] must read as one
              pmp_addr_rdata[i] = {pmp_addr_q[i], {PMP_GRANULARITY-1{1'b1}}};

              if ((pmpncfg_q[i].mode == PMP_MODE_OFF) ||
                  (pmpncfg_q[i].mode == PMP_MODE_TOR)) begin
              // In TOR or OFF mode, bits [G-1:0] must read as zero
                pmp_addr_rdata[i][PMP_GRANULARITY-1:0] = '0;
              end
            end
          end

          assign csr_pmp_o.addr[i] = {pmp_addr_rdata[i], 2'b00};

        end // if (i < PMP_NUM_REGIONS)
        else begin: no_pmp_region

          // Tie off outputs for unimplemeted regions
          assign pmp_addr_we[i]    = 1'b0;
          assign pmp_addr_rdata[i] = '0;

          assign csr_pmp_o.addr[i] = '0;
          assign csr_pmp_o.cfg[i]  = pmpncfg_t'('0);

          assign pmp_addr_q[i] = '0;
          assign pmpncfg_q[i]  = pmpncfg_t'('0);
          assign pmpncfg_n[i]  = pmpncfg_t'('0);
          assign pmpncfg_we[i] = 1'b0;
        end
      end


      // MSECCFG.MML/MSECCFG.MMWP cannot be unset once set
      assign pmp_mseccfg_n.mml  = csr_wdata_int[CSR_MSECCFG_MML_BIT]  || pmp_mseccfg_q.mml;
      assign pmp_mseccfg_n.mmwp = csr_wdata_int[CSR_MSECCFG_MMWP_BIT] || pmp_mseccfg_q.mmwp;


      // MSECCFG.RLB cannot be set if RLB=0 and any PMP region is locked
      assign pmp_mseccfg_n.rlb  = pmp_mseccfg_q.rlb ? csr_wdata_int[CSR_MSECCFG_RLB_BIT] :
                                  csr_wdata_int[CSR_MSECCFG_RLB_BIT] && !(|pmpncfg_locked);

      assign pmp_mseccfg_n.zero0 = '0;

      cv32e40s_csr #(
                     .LIB        (LIB),
                     .WIDTH      ($bits(mseccfg_t)),
                     .MASK       (CSR_MSECCFG_MASK),
                     .SHADOWCOPY (SECURE),
                     .RESETVALUE (PMP_MSECCFG_RV))
      pmp_mseccfg_csr_i
        (.clk        (clk),
         .rst_n      (rst_n),
         .scan_cg_en_i (scan_cg_en_i),
         .wr_data_i  (pmp_mseccfg_n),
         .wr_en_i    (pmp_mseccfg_we),
         .rd_data_o  (pmp_mseccfg_q),
         .rd_error_o (pmp_mseccfg_rd_error));

      assign csr_pmp_o.mseccfg = pmp_mseccfg_q;

      // Combine read error signals
      assign pmp_rd_error = |pmpncfg_rd_error ||
                            |pmp_addr_rd_error ||
                            pmp_mseccfg_rd_error;

    end
    else begin: no_csr_pmp
      // Generate tieoffs when PMP is not configured
      for (genvar i = 0; i < PMP_MAX_REGIONS; i++) begin : g_tie_pmp_rdata
        assign pmp_addr_rdata[i] = '0;
        assign csr_pmp_o.cfg[i]  = pmpncfg_t'('0);
        assign csr_pmp_o.addr[i] = '0;
      end

      assign csr_pmp_o.mseccfg = mseccfg_t'('0);
      assign pmp_rd_error = 1'b0;

    end
  endgenerate

  assign mintthresh_o = mintthresh_q[7:0];
  assign mintstatus_o = mintstatus_q;
  // dcsr_rdata factors in the flop outputs and the nmip bit from the controller
  assign dcsr_rdata = {dcsr_q[31:4], ctrl_fsm_i.pending_nmi, dcsr_q[2:0]};

 ////////////////////////////////////////////////////////////////////////
 //  ____       _                   _____     _                        //
 // |  _ \  ___| |__  _   _  __ _  |_   _| __(_) __ _  __ _  ___ _ __  //
 // | | | |/ _ \ '_ \| | | |/ _` |   | || '__| |/ _` |/ _` |/ _ \ '__| //
 // | |_| |  __/ |_) | |_| | (_| |   | || |  | | (_| | (_| |  __/ |    //
 // |____/ \___|_.__/ \__,_|\__, |   |_||_|  |_|\__, |\__, |\___|_|    //
 //                         |___/               |___/ |___/            //
 ////////////////////////////////////////////////////////////////////////


  // Write select
  assign tmatch_control_we = csr_we_int && ctrl_fsm_i.debug_mode && (csr_waddr == CSR_TDATA1);
  assign tmatch_value_we   = csr_we_int && ctrl_fsm_i.debug_mode && (csr_waddr == CSR_TDATA2);

  // All supported trigger types
  assign tinfo_types = 1 << TTYPE_MCONTROL;

  // Assign write data
  // TDATA0 - only support simple address matching
  assign tmatch_control_n =
              {
              TTYPE_MCONTROL,        // type    : address/data match
              1'b1,                  // dmode   : access from D mode only
              6'h00,                 // maskmax : exact match only
              1'b0,                  // hit     : not supported
              1'b0,                  // select  : address match only
              1'b0,                  // timing  : match before execution
              2'b00,                 // sizelo  : match any access
              4'h1,                  // action  : enter debug mode
              1'b0,                  // chain   : not supported
              4'h0,                  // match   : simple match
              1'b1,                  // m       : match in m-mode
              1'b0,                  // 0       : zero
              1'b0,                  // s       : not supported
              1'b0,                  // u       : match in u-mode
              csr_wdata_int[2],      // execute : match instruction address
              1'b0,                  // store   : not supported
              1'b0};                 // load    : not supported

  assign tmatch_value_n = csr_wdata_int;

  cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      (32),
    .SHADOWCOPY (1'b0),
    .RESETVALUE (TMATCH_CONTROL_RST_VAL)
  ) tmatch_control_csr_i (
    .clk      (clk),
    .rst_n     (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (tmatch_control_n),
    .wr_en_i    (tmatch_control_we),
    .rd_data_o  (tmatch_control_q),
    .rd_error_o (tmatch_control_rd_error)
  );

  cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      (32),
    .SHADOWCOPY (1'b0),
    .RESETVALUE (32'd0)
  ) tmatch_value_csr_i (
    .clk      (clk),
    .rst_n     (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (tmatch_value_n),
    .wr_en_i    (tmatch_value_we),
    .rd_data_o  (tmatch_value_q),
    .rd_error_o (tmatch_value_rd_error)
  );


  // Breakpoint matching
  // We match against the next address, as the breakpoint must be taken before execution
  // Matching is disabled when ctrl_fsm_i.debug_mode == 1'b1
  // Trigger CSRs can only be written from debug mode, writes from any other privilege level are ignored.
  //   Thus we do not have an issue where a write to the tdata2 CSR immediately before the matched instruction
  //   could be missed since we must write in debug mode, then dret to machine mode (kills pipeline) before
  //   returning to dpc.
  //   Todo: There is no CLIC spec for trigger matches for pointers.
  assign trigger_match_o = tmatch_control_q[2] && !ctrl_fsm_i.debug_mode && !ptr_in_if_i &&
                           (pc_if_i[31:0] == tmatch_value_q[31:0]);


  /////////////////////////////////////////////////////////////////
  //   ____            __     ____                  _            //
  // |  _ \ ___ _ __ / _|   / ___|___  _   _ _ __ | |_ ___ _ __  //
  // | |_) / _ \ '__| |_   | |   / _ \| | | | '_ \| __/ _ \ '__| //
  // |  __/  __/ |  |  _|  | |__| (_) | |_| | | | | ||  __/ |    //
  // |_|   \___|_|  |_|(_)  \____\___/ \__,_|_| |_|\__\___|_|    //
  //                                                             //
  /////////////////////////////////////////////////////////////////

  // Cycle Count Output Signal
  assign mcycle_o = mhpmcounter_q[0];

  // Flop certain events to ease timing
  localparam bit [15:0] HPM_EVENT_FLOP     = 16'b1111_1111_1100_0000;
  localparam bit [31:0] MCOUNTINHIBIT_MASK = {{(29-NUM_MHPMCOUNTERS){1'b0}},{(NUM_MHPMCOUNTERS){1'b1}},3'b101};

  logic [15:0]          hpm_events_raw;
  logic                 all_counters_disabled;

  assign all_counters_disabled = &(mcountinhibit_n | ~MCOUNTINHIBIT_MASK);

  genvar                hpm_idx;
  generate
    for(hpm_idx=0; hpm_idx<16; hpm_idx++) begin
      if(HPM_EVENT_FLOP[hpm_idx]) begin: hpm_event_flop

        always_ff @(posedge clk, negedge rst_n) begin
          if (rst_n == 1'b0) begin
            hpm_events[hpm_idx] <= 1'b0;
          end else begin
            if(!all_counters_disabled) begin
              hpm_events[hpm_idx] <= hpm_events_raw[hpm_idx];
            end
          end
        end

      end
      else begin: hpm_even_no_flop
        assign hpm_events[hpm_idx] = hpm_events_raw[hpm_idx];
      end
    end
  endgenerate

  // ------------------------
  // Events to count
  assign hpm_events_raw[0]  = 1'b1;                               // Cycle counter
  assign hpm_events_raw[1]  = ctrl_fsm_i.mhpmevent.minstret;      // Instruction counter
  assign hpm_events_raw[2]  = ctrl_fsm_i.mhpmevent.compressed;    // Compressed instruction counter
  assign hpm_events_raw[3]  = ctrl_fsm_i.mhpmevent.jump;          // Nr of jumps (unconditional)
  assign hpm_events_raw[4]  = ctrl_fsm_i.mhpmevent.branch;        // Nr of branches (conditional)
  assign hpm_events_raw[5]  = ctrl_fsm_i.mhpmevent.branch_taken;  // Nr of taken branches (conditional)
  assign hpm_events_raw[6]  = ctrl_fsm_i.mhpmevent.intr_taken;    // Nr of interrupts taken (excluding NMI)
  assign hpm_events_raw[7]  = ctrl_fsm_i.mhpmevent.data_read;     // Data read. Nr of read transactions on the OBI data interface
  assign hpm_events_raw[8]  = ctrl_fsm_i.mhpmevent.data_write;    // Data write. Nr of write transactions on the OBI data interface
  assign hpm_events_raw[9]  = ctrl_fsm_i.mhpmevent.if_invalid;    // IF invalid (No valid output from IF when ID stage is ready)
  assign hpm_events_raw[10] = ctrl_fsm_i.mhpmevent.id_invalid;    // ID invalid (No valid output from ID when EX stage is ready)
  assign hpm_events_raw[11] = ctrl_fsm_i.mhpmevent.ex_invalid;    // EX invalid (No valid output from EX when WB stage is ready)
  assign hpm_events_raw[12] = ctrl_fsm_i.mhpmevent.wb_invalid;    // WB invalid (No valid output from WB)
  assign hpm_events_raw[13] = ctrl_fsm_i.mhpmevent.id_ld_stall;   // Nr of load use hazards
  assign hpm_events_raw[14] = ctrl_fsm_i.mhpmevent.id_jalr_stall; // Nr of jump (and link) register hazards
  assign hpm_events_raw[15] = ctrl_fsm_i.mhpmevent.wb_data_stall; // Nr of stall cycles caused in the WB stage by loads/stores

  // ------------------------
  // address decoder for performance counter registers
  logic mcountinhibit_we;
  logic mhpmevent_we;

  assign mcountinhibit_we = csr_we_int & (  csr_waddr == CSR_MCOUNTINHIBIT);
  assign mhpmevent_we     = csr_we_int & ( (csr_waddr == CSR_MHPMEVENT3  )||
                                           (csr_waddr == CSR_MHPMEVENT4  ) ||
                                           (csr_waddr == CSR_MHPMEVENT5  ) ||
                                           (csr_waddr == CSR_MHPMEVENT6  ) ||
                                           (csr_waddr == CSR_MHPMEVENT7  ) ||
                                           (csr_waddr == CSR_MHPMEVENT8  ) ||
                                           (csr_waddr == CSR_MHPMEVENT9  ) ||
                                           (csr_waddr == CSR_MHPMEVENT10 ) ||
                                           (csr_waddr == CSR_MHPMEVENT11 ) ||
                                           (csr_waddr == CSR_MHPMEVENT12 ) ||
                                           (csr_waddr == CSR_MHPMEVENT13 ) ||
                                           (csr_waddr == CSR_MHPMEVENT14 ) ||
                                           (csr_waddr == CSR_MHPMEVENT15 ) ||
                                           (csr_waddr == CSR_MHPMEVENT16 ) ||
                                           (csr_waddr == CSR_MHPMEVENT17 ) ||
                                           (csr_waddr == CSR_MHPMEVENT18 ) ||
                                           (csr_waddr == CSR_MHPMEVENT19 ) ||
                                           (csr_waddr == CSR_MHPMEVENT20 ) ||
                                           (csr_waddr == CSR_MHPMEVENT21 ) ||
                                           (csr_waddr == CSR_MHPMEVENT22 ) ||
                                           (csr_waddr == CSR_MHPMEVENT23 ) ||
                                           (csr_waddr == CSR_MHPMEVENT24 ) ||
                                           (csr_waddr == CSR_MHPMEVENT25 ) ||
                                           (csr_waddr == CSR_MHPMEVENT26 ) ||
                                           (csr_waddr == CSR_MHPMEVENT27 ) ||
                                           (csr_waddr == CSR_MHPMEVENT28 ) ||
                                           (csr_waddr == CSR_MHPMEVENT29 ) ||
                                           (csr_waddr == CSR_MHPMEVENT30 ) ||
                                           (csr_waddr == CSR_MHPMEVENT31 ) );

  // ------------------------
  // Increment value for performance counters
  genvar incr_gidx;
  generate
    for (incr_gidx=0; incr_gidx<32; incr_gidx++) begin : gen_mhpmcounter_increment
      assign mhpmcounter_increment[incr_gidx] = mhpmcounter_q[incr_gidx] + 1;
    end
  endgenerate

  // ------------------------
  // next value for performance counters and control registers
  always_comb
    begin
      mcountinhibit_n = mcountinhibit_q;
      mhpmevent_n     = mhpmevent_q;


      // Inhibit Control
      if(mcountinhibit_we)
        mcountinhibit_n = csr_wdata_int & MCOUNTINHIBIT_MASK;

      // Event Control
      if(mhpmevent_we)
        mhpmevent_n[csr_waddr[4:0]] = csr_wdata_int;
    end

  genvar wcnt_gidx;
  generate
    for (wcnt_gidx=0; wcnt_gidx<32; wcnt_gidx++) begin : gen_mhpmcounter_write

      // Write lower counter bits
      assign mhpmcounter_write_lower[wcnt_gidx] = csr_we_int && (csr_waddr == (CSR_MCYCLE + wcnt_gidx));

      // Write upper counter bits
      assign mhpmcounter_write_upper[wcnt_gidx] = !mhpmcounter_write_lower[wcnt_gidx] &&
                                                  csr_we_int && (csr_waddr == (CSR_MCYCLEH + wcnt_gidx)) && (MHPMCOUNTER_WIDTH == 64);

      // Increment counter

      if (wcnt_gidx == 0) begin : gen_mhpmcounter_mcycle
        // mcycle = mhpmcounter[0] : count every cycle (if not inhibited)
        assign mhpmcounter_write_increment[wcnt_gidx] = !mhpmcounter_write_lower[wcnt_gidx] &&
                                                        !mhpmcounter_write_upper[wcnt_gidx] &&
                                                        !mcountinhibit_q[wcnt_gidx];
      end else if (wcnt_gidx == 2) begin : gen_mhpmcounter_minstret
        // minstret = mhpmcounter[2]  : count every retired instruction (if not inhibited)
        assign mhpmcounter_write_increment[wcnt_gidx] = !mhpmcounter_write_lower[wcnt_gidx] &&
                                                        !mhpmcounter_write_upper[wcnt_gidx] &&
                                                        !mcountinhibit_q[wcnt_gidx] &&
                                                        hpm_events[1];
      end else if( (wcnt_gidx>2) && (wcnt_gidx<(NUM_MHPMCOUNTERS+3))) begin : gen_mhpmcounter
        // add +1 if any event is enabled and active
        assign mhpmcounter_write_increment[wcnt_gidx] = !mhpmcounter_write_lower[wcnt_gidx] &&
                                                        !mhpmcounter_write_upper[wcnt_gidx] &&
                                                        !mcountinhibit_q[wcnt_gidx] &&
                                                        |(hpm_events & mhpmevent_q[wcnt_gidx][NUM_HPM_EVENTS-1:0]);
      end else begin : gen_mhpmcounter_not_implemented
        assign mhpmcounter_write_increment[wcnt_gidx] = 1'b0;
      end

    end
  endgenerate

  // ------------------------
  // HPM Registers
  // next value
  genvar nxt_gidx;
  generate
    for (nxt_gidx = 0; nxt_gidx < 32; nxt_gidx++) begin : gen_mhpmcounter_nextvalue
      // mcyclce  is located at index 0
      // there is no counter at index 1
      // minstret is located at index 2
      // Programable HPM counters start at index 3
      if( (nxt_gidx == 1) ||
          (nxt_gidx >= (NUM_MHPMCOUNTERS+3) ) )
        begin : gen_non_implemented
          assign mhpmcounter_n[nxt_gidx]  = 'b0;
          assign mhpmcounter_we[nxt_gidx] = 2'b0;
      end
      else begin : gen_implemented_nextvalue
        always_comb begin
          mhpmcounter_we[nxt_gidx] = 2'b0;
          mhpmcounter_n[nxt_gidx]  = mhpmcounter_q[nxt_gidx];
          if (mhpmcounter_write_lower[nxt_gidx]) begin
            mhpmcounter_n[nxt_gidx][31:0] = csr_wdata_int;
            mhpmcounter_we[nxt_gidx][0] = 1'b1;
          end else if (mhpmcounter_write_upper[nxt_gidx]) begin
            mhpmcounter_n[nxt_gidx][63:32] = csr_wdata_int;
            mhpmcounter_we[nxt_gidx][1] = 1'b1;
          end else if (mhpmcounter_write_increment[nxt_gidx]) begin
            mhpmcounter_we[nxt_gidx] = 2'b11;
            mhpmcounter_n[nxt_gidx] = mhpmcounter_increment[nxt_gidx];
          end
        end // always_comb
      end
    end
  endgenerate
  //  Counter Registers: mhpcounter_q[]
  genvar cnt_gidx;
  generate
    for (cnt_gidx = 0; cnt_gidx < 32; cnt_gidx++) begin : gen_mhpmcounter
      // mcyclce  is located at index 0
      // there is no counter at index 1
      // minstret is located at index 2
      // Programable HPM counters start at index 3
      if( (cnt_gidx == 1) ||
          (cnt_gidx >= (NUM_MHPMCOUNTERS+3) ) )
        begin : gen_non_implemented
        assign mhpmcounter_q[cnt_gidx] = 'b0;
      end
      else begin : gen_implemented
        always_ff @(posedge clk, negedge rst_n)
          if (!rst_n) begin
            mhpmcounter_q[cnt_gidx] <= 'b0;
          end else begin
            if (mhpmcounter_we[cnt_gidx][0]) begin
              mhpmcounter_q[cnt_gidx][31:0] <= mhpmcounter_n[cnt_gidx][31:0];
            end
            if (mhpmcounter_we[cnt_gidx][1]) begin
              mhpmcounter_q[cnt_gidx][63:32] <= mhpmcounter_n[cnt_gidx][63:32];
            end
          end
      end
    end
  endgenerate

  //  Event Register: mhpevent_q[]
  genvar evt_gidx;
  generate
    for (evt_gidx = 0; evt_gidx < 32; evt_gidx++) begin : gen_mhpmevent
      // programable HPM events start at index3
      if( (evt_gidx < 3) ||
          (evt_gidx >= (NUM_MHPMCOUNTERS+3) ) )
        begin : gen_non_implemented
        assign mhpmevent_q[evt_gidx] = 'b0;
      end
      else begin : gen_implemented
        if (NUM_HPM_EVENTS < 32) begin : gen_tie_off
             assign mhpmevent_q[evt_gidx][31:NUM_HPM_EVENTS] = 'b0;
        end
        always_ff @(posedge clk, negedge rst_n)
            if (!rst_n)
                mhpmevent_q[evt_gidx][NUM_HPM_EVENTS-1:0]  <= 'b0;
            else
                mhpmevent_q[evt_gidx][NUM_HPM_EVENTS-1:0]  <= mhpmevent_n[evt_gidx][NUM_HPM_EVENTS-1:0] ;
      end
    end
  endgenerate

  //  Inhibit Regsiter: mcountinhibit_q
  //  Note: implemented counters are disabled out of reset to save power
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      mcountinhibit_q <= MCOUNTINHIBIT_MASK; // default disable
    end else begin
      mcountinhibit_q <= mcountinhibit_n;
    end
  end

  //  Counter enable register: mcounteren
  //  mcounteren[2:0] = {IR, TM, CY}. time (TM) is not implemented
  localparam logic [31:0] MCOUNTEREN_MASK = {{(29-NUM_MHPMCOUNTERS){1'b0}},{(NUM_MHPMCOUNTERS){1'b1}},3'b101};


  cv32e40s_csr #(
    .LIB        (LIB),
    .WIDTH      (32),
    .SHADOWCOPY (1'b0),
    .RESETVALUE (32'd0),
    .MASK       (MCOUNTEREN_MASK)
  ) mcounteren_csr_i (
    .clk        (clk),
    .rst_n      (rst_n),
    .scan_cg_en_i (scan_cg_en_i),
    .wr_data_i  (mcounteren_n),
    .wr_en_i    (mcounteren_we),
    .rd_data_o  (mcounteren_q),
    .rd_error_o (mcounteren_rd_error));

endmodule // cv32e40s_cs_registers
