-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:					Thomas B. Preusser
--                  Gustavo Martin
--
-- Entity:					fifo_ic_assembly_TestHarness
--
-- Description:
-- -------------------------------------
-- Test harness for fifo_ic_assembly OSVVM testbench
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

use     work.fifo_ic_assembly_TestController_pkg.all;

entity fifo_ic_assembly_TestHarness is
end entity;

architecture TestHarness of fifo_ic_assembly_TestHarness is
  constant TPERIOD_CLOCK : time := 10 ns;

  signal Clock : std_logic := '1';
  signal Reset : std_logic := '0';  -- No reset needed in original test

  -- Write interface signals
  signal base : tAddrWord;
  signal addr : tAddrWord;
  signal din  : tDataWord;
  signal put  : std_logic;

  -- Read interface signals
  signal dout  : tDataWord;
  signal valid : std_logic;
  signal got   : std_logic;

  component fifo_ic_assembly_TestController is
    port (
      Clock : in  std_logic;
      Reset : in  std_logic;
      base  : in  tAddrWord;
      addr  : out tAddrWord;
      din   : out tDataWord;
      put   : out std_logic;
      dout  : in  tDataWord;
      valid : in  std_logic;
      got   : out std_logic
    );
  end component;

begin
  -- Clock generation
  Osvvm.ClockResetPkg.CreateClock(
    Clk    => Clock,
    Period => TPERIOD_CLOCK
  );

  -- DUT instantiation
  DUT : entity PoC.fifo_ic_assembly
    generic map (
      D_BITS => D_BITS,
      A_BITS => A_BITS,
      G_BITS => G_BITS
    )
    port map (
      clk_wr => Clock,
      rst_wr => Reset,
      base   => base,
      addr   => addr,
      din    => din,
      put    => put,
      clk_rd => Clock,
      rst_rd => Reset,
      dout   => dout,
      vld    => valid,
      got    => got
    );

  -- Test Controller instantiation
  TestCtrl : component fifo_ic_assembly_TestController
    port map (
      Clock => Clock,
      Reset => Reset,
      base  => base,
      addr  => addr,
      din   => din,
      put   => put,
      dout  => dout,
      valid => valid,
      got   => got
    );

end architecture;
