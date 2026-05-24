// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Tim Fischer <fischeti@iis.ee.ethz.ch>

`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "tcdm_interface/typedef.svh"

module cluster_tile
  import snitch_cluster_pkg::*;
(
  input  logic                                    clk_i,
  input  logic                                    rst_ni,
  // input  logic                                    test_enable_i,
  // input  logic                                    tile_clk_en_i,
  // input  logic                                    tile_rst_ni,
  // input  logic                                    clk_rst_bypass_i,
  // Cluster ports
  input  logic                      [NrCores-1:0] debug_req_i,
  input  logic                      [NrCores-1:0] meip_i,
  input  logic                      [NrCores-1:0] mtip_i,
  input  logic                      [NrCores-1:0] msip_i,
  input  logic                      [        9:0] hart_base_id_i,
  input  snitch_cluster_pkg::addr_t               cluster_base_addr_i,
  input  snitch_cluster_pkg::sram_cfgs_t         sram_cfgs_i,
  input snitch_cluster_pkg::narrow_in_req_t   cluster_narrow_in_req_i,
  output snitch_cluster_pkg::narrow_in_resp_t  cluster_narrow_in_resp_o,
  output snitch_cluster_pkg::narrow_out_req_t  cluster_narrow_out_req_o,
  input snitch_cluster_pkg::narrow_out_resp_t cluster_narrow_out_resp_i,
  output snitch_cluster_pkg::wide_out_req_t    cluster_wide_out_req_o,
  input snitch_cluster_pkg::wide_out_resp_t   cluster_wide_out_resp_i,
  input snitch_cluster_pkg::wide_in_req_t     cluster_wide_in_req_i,
  output snitch_cluster_pkg::wide_in_resp_t    cluster_wide_in_resp_o
);

  // Tile-specific reset and clock signals
  // logic                                 tile_clk;
  logic                                 tile_rst_n;

  ////////////////////
  // Snitch Cluster //
  ////////////////////


  snitch_cluster_pkg::narrow_out_req_t  cluster_narrow_ext_req;
  snitch_cluster_pkg::narrow_out_resp_t cluster_narrow_ext_rsp;
  snitch_cluster_pkg::tcdm_dma_req_t    cluster_tcdm_ext_req;
  snitch_cluster_pkg::tcdm_dma_rsp_t    cluster_tcdm_ext_rsp;

  localparam int unsigned HWPECtrlAddrWidth = 32;
  localparam int unsigned HWPECtrlDataWidth = 32;
  typedef logic [HWPECtrlAddrWidth-1:0] addr_hwpe_ctrl_t;
  typedef logic [HWPECtrlDataWidth-1:0] data_hwpe_ctrl_t;
  typedef logic [3:0] strb_hwpe_ctrl_t;

  `AXI_TYPEDEF_ALL(cluster_narrow_out_dw_conv, snitch_cluster_pkg::addr_t,
                   snitch_cluster_pkg::narrow_out_id_t, data_hwpe_ctrl_t, strb_hwpe_ctrl_t,
                   snitch_cluster_pkg::user_narrow_t)

  cluster_narrow_out_dw_conv_req_t cluster_narrow_out_dw_conv_req, cluster_narrow_out_cut_req;
  cluster_narrow_out_dw_conv_resp_t cluster_narrow_out_dw_conv_rsp, cluster_narrow_out_cut_rsp;

  `TCDM_TYPEDEF_ALL(hwpectrl, addr_hwpe_ctrl_t, data_hwpe_ctrl_t, strb_hwpe_ctrl_t, logic)

  hwpectrl_req_t               hwpectrl_req;
  hwpectrl_rsp_t               hwpectrl_rsp;

  logic          [NrCores-1:0] mxip;

  snitch_cluster_wrapper i_cluster_wrapper (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .debug_req_i,
    .meip_i,
    .mtip_i,
    .msip_i,
    .hart_base_id_i,
    .cluster_base_addr_i,
    .mxip_i           (mxip),
    .clk_d2_bypass_i  ('0),
    .sram_cfgs_i,
    .narrow_in_req_i  (cluster_narrow_in_req_i), // chimney? 
    .narrow_in_resp_o (cluster_narrow_in_resp_o), // chimney?
    .narrow_out_req_o (cluster_narrow_out_req_o), // chimney?
    .narrow_out_resp_i(cluster_narrow_out_resp_i), // chimney?
    .wide_out_req_o   (cluster_wide_out_req_o), // chimney?
    .wide_out_resp_i  (cluster_wide_out_resp_i), // chimney?
    .wide_in_req_i    (cluster_wide_in_req_i), // chimney?
    .wide_in_resp_o   (cluster_wide_in_resp_o), // chimney?
    .narrow_ext_req_o (cluster_narrow_ext_req), // AXI DW converter -> AXI cut -> AXI to TCDM -> HWPE
    .narrow_ext_resp_i(cluster_narrow_ext_rsp), // AXI DW converter -> AXI cut -> AXI to TCDM -> HWPE
    .tcdm_ext_req_i   (cluster_tcdm_ext_req), // to HWPE
    .tcdm_ext_resp_o  (cluster_tcdm_ext_rsp) // to HWPE
  );

  // Convert narrow AXI's 64 bit DW down to 32
  axi_dw_converter #(
    .AxiMaxReads        (1),
    .AxiSlvPortDataWidth(snitch_cluster_pkg::NarrowDataWidth),
    .AxiMstPortDataWidth(HWPECtrlDataWidth),
    .AxiAddrWidth       (snitch_cluster_pkg::AddrWidth),
    .AxiIdWidth         (snitch_cluster_pkg::NarrowIdWidthOut),
    .aw_chan_t          (snitch_cluster_pkg::narrow_out_aw_chan_t),
    .mst_w_chan_t       (cluster_narrow_out_dw_conv_w_chan_t),
    .slv_w_chan_t       (snitch_cluster_pkg::narrow_out_w_chan_t),
    .b_chan_t           (snitch_cluster_pkg::narrow_out_b_chan_t),
    .ar_chan_t          (snitch_cluster_pkg::narrow_out_ar_chan_t),
    .mst_r_chan_t       (cluster_narrow_out_dw_conv_r_chan_t),
    .slv_r_chan_t       (snitch_cluster_pkg::narrow_out_r_chan_t),
    .axi_mst_req_t      (cluster_narrow_out_dw_conv_req_t),
    .axi_mst_resp_t     (cluster_narrow_out_dw_conv_resp_t),
    .axi_slv_req_t      (snitch_cluster_pkg::narrow_out_req_t),
    .axi_slv_resp_t     (snitch_cluster_pkg::narrow_out_resp_t)
  ) i_axi_dw_hwpe (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .slv_req_i (cluster_narrow_ext_req),
    .slv_resp_o(cluster_narrow_ext_rsp),
    .mst_req_o (cluster_narrow_out_dw_conv_req),
    .mst_resp_i(cluster_narrow_out_dw_conv_rsp)
  );

  axi_cut #(
    .Bypass    (0),
    .aw_chan_t (snitch_cluster_pkg::narrow_out_aw_chan_t),
    .w_chan_t  (cluster_narrow_out_dw_conv_w_chan_t),
    .b_chan_t  (snitch_cluster_pkg::narrow_out_b_chan_t),
    .ar_chan_t (snitch_cluster_pkg::narrow_out_ar_chan_t),
    .r_chan_t  (cluster_narrow_out_dw_conv_r_chan_t),
    .axi_req_t (cluster_narrow_out_dw_conv_req_t),
    .axi_resp_t(cluster_narrow_out_dw_conv_resp_t)
  ) i_cut_ext_narrow_slv (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .slv_req_i (cluster_narrow_out_dw_conv_req),
    .slv_resp_o(cluster_narrow_out_dw_conv_rsp),
    .mst_req_o (cluster_narrow_out_cut_req),
    .mst_resp_i(cluster_narrow_out_cut_rsp)
  );

  axi_to_tcdm #(
    .axi_req_t (cluster_narrow_out_dw_conv_req_t),
    .axi_rsp_t (cluster_narrow_out_dw_conv_resp_t),
    .tcdm_req_t(hwpectrl_req_t),
    .tcdm_rsp_t(hwpectrl_rsp_t),
    .IdWidth   (snitch_cluster_pkg::NarrowIdWidthOut),
    .AddrWidth (HWPECtrlAddrWidth),
    .DataWidth (HWPECtrlDataWidth)
  ) i_axi_to_hwpe_ctrl (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .axi_req_i (cluster_narrow_out_cut_req),
    .axi_rsp_o (cluster_narrow_out_cut_rsp),
    .tcdm_req_o(hwpectrl_req),
    .tcdm_rsp_i(hwpectrl_rsp)
  );


  snitch_hwpe_subsystem #(
    .tcdm_req_t   (snitch_cluster_pkg::tcdm_dma_req_t),
    .tcdm_rsp_t   (snitch_cluster_pkg::tcdm_dma_rsp_t),
    .periph_req_t (hwpectrl_req_t),
    .periph_rsp_t (hwpectrl_rsp_t),
    .HwpeDataWidth(snitch_cluster_pkg::WideDataWidth),
    .IdWidth      (snitch_cluster_pkg::NarrowIdWidthOut),
    .NrCores      (NrCores),
    .TCDMDataWidth(snitch_cluster_pkg::NarrowDataWidth)
  ) i_snitch_hwpe_subsystem (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .test_mode_i    (1'b0),
    .tcdm_req_o     (cluster_tcdm_ext_req),
    .tcdm_rsp_i     (cluster_tcdm_ext_rsp),
    .hwpe_ctrl_req_i(hwpectrl_req),
    .hwpe_ctrl_rsp_o(hwpectrl_rsp),
    .hwpe_evt_o     (mxip)
  );

  //////////////////////////
  // Clock Gating & Reset //
  //////////////////////////

  /*
  tc_clk_gating i_tc_clk_gating_cluster (
    .clk_i,
    .en_i     (tile_clk_en_i),
    .test_en_i(clk_rst_bypass_i),
    .clk_o    (tile_clk)
  );

`ifdef TARGET_XILINX
  // Using clk cells makes Vivado flag the reset as a clock tree
  assign tile_rst_n = (clk_rst_bypass_i) ? rst_ni : tile_rst_ni;
`else
  tc_clk_mux2 i_tc_reset_mux (
    .clk0_i   (tile_rst_ni),
    .clk1_i   (rst_ni),
    .clk_sel_i(clk_rst_bypass_i),
    .clk_o    (tile_rst_n)
  );
`endif
*/


endmodule
