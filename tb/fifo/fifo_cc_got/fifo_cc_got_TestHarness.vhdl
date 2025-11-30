-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:					Thomas B. Preusser
--                  Gustavo Martin
--
-- Entity:					fifo_cc_got_TestHarness
--
-- Description:
-- -------------------------------------
-- Test harness for fifo_cc_got OSVVM testbench
-- Instantiates DUT and TestController for each configuration variant
--
-- License:
-- =============================================================================
-- Copyright 2025-2025 The PoC-Library Authors
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--		http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
-- =============================================================================

library IEEE;
use     IEEE.std_logic_1164.all;
use     IEEE.numeric_std.all;

library osvvm;
context osvvm.OsvvmContext;

library PoC;

use     work.fifo_cc_got_TestController_pkg.all;

entity fifo_cc_got_TestHarness is
  generic (
    CONFIG_INDEX : tConfigIndex := 0
  );
end entity;

architecture TestHarness of fifo_cc_got_TestHarness is
  constant TPERIOD_CLOCK : time := 10 ns;

  signal Clock : std_logic := '1';
  signal Reset : std_logic := '1';

  -- Write interface signals
  signal put       : std_logic;
  signal din       : tDataWord;
  signal full      : std_logic;
  signal estate_wr : std_logic_vector(ESTATE_WR_BITS-1 downto 0);

  -- Read interface signals
  signal got       : std_logic;
  signal dout      : tDataWord;
  signal valid     : std_logic;
  signal fstate_rd : std_logic_vector(FSTATE_RD_BITS-1 downto 0);

  component fifo_cc_got_TestController is
    generic (
      CONFIG_INDEX : tConfigIndex := 0
    );
    port (
      Clock     : in  std_logic;
      Reset     : in  std_logic;
      put       : out std_logic;
      din       : out tDataWord;
      full      : in  std_logic;
      estate_wr : in  std_logic_vector(ESTATE_WR_BITS-1 downto 0);
      got       : out std_logic;
      dout      : in  tDataWord;
      valid     : in  std_logic;
      fstate_rd : in  std_logic_vector(FSTATE_RD_BITS-1 downto 0)
    );
  end component;

begin
  -- Clock generation
  Osvvm.ClockResetPkg.CreateClock(
    Clk    => Clock,
    Period => TPERIOD_CLOCK
  );

  -- Reset generation
  Osvvm.ClockResetPkg.CreateReset(
    Reset       => Reset,
    ResetActive => '1',
    Clk         => Clock,
    Period      => 5 * TPERIOD_CLOCK,
    tpd         => 0 ns
  );

  -- DUT instantiation
  DUT : entity PoC.fifo_cc_got
    generic map (
      D_BITS         => D_BITS,
      MIN_DEPTH      => MIN_DEPTH,
      DATA_REG       => GetDataReg(CONFIG_INDEX),
      STATE_REG      => GetStateReg(CONFIG_INDEX),
      OUTPUT_REG     => GetOutputReg(CONFIG_INDEX),
      ESTATE_WR_BITS => ESTATE_WR_BITS,
      FSTATE_RD_BITS => FSTATE_RD_BITS
    )
    port map (
      rst       => Reset,
      clk       => Clock,
      put       => put,
      din       => din,
      full      => full,
      estate_wr => estate_wr,
      got       => got,
      dout      => dout,
      valid     => valid,
      fstate_rd => fstate_rd
    );

  -- Test Controller instantiation
  TestCtrl : component fifo_cc_got_TestController
    generic map (
      CONFIG_INDEX => CONFIG_INDEX
    )
    port map (
      Clock     => Clock,
      Reset     => Reset,
      put       => put,
      din       => din,
      full      => full,
      estate_wr => estate_wr,
      got       => got,
      dout      => dout,
      valid     => valid,
      fstate_rd => fstate_rd
    );

end architecture;
