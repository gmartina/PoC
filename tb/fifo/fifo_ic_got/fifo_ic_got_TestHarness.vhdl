-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:					Thomas B. Preusser
--                  Gustavo Martin
--
-- Entity:					fifo_ic_got_TestHarness
--
-- Description:
-- -------------------------------------
-- Test harness for fifo_ic_got OSVVM testbench
-- Tests cross-clock domain FIFO with chain of two FIFOs:
-- clk0 -> FIFO0 -> clk1 -> FIFO1 -> clk2
-- Uses different clock frequencies to stress CDC
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

use     work.fifo_ic_got_TestController_pkg.all;

entity fifo_ic_got_TestHarness is
end entity;

architecture TestHarness of fifo_ic_got_TestHarness is
  -- Different clock periods to stress CDC
  constant TPERIOD_CLK0 : time := 14 ns;  -- ~71.4 MHz
  constant TPERIOD_CLK1 : time := 24 ns;  -- ~41.7 MHz
  constant TPERIOD_CLK2 : time := 10 ns;  -- 100 MHz

  signal Clock0 : std_logic := '1';
  signal Clock1 : std_logic := '1';
  signal Clock2 : std_logic := '1';
  signal Reset  : std_logic := '1';

  -- FIFO 0->1 signals (clk0 write, clk1 read)
  signal di0       : tDataWord;
  signal put0      : std_logic;
  signal full0     : std_logic;
  signal do1       : tDataWord;
  signal valid1    : std_logic;
  signal got1      : std_logic;

  -- FIFO 1->2 signals (clk1 write, clk2 read)
  signal di1       : tDataWord;
  signal put1      : std_logic;
  signal full1     : std_logic;
  signal do2       : tDataWord;
  signal valid2    : std_logic;
  signal got2      : std_logic;
  signal dat2      : tDataWord;

  -- Intermediate scrambler signals
  signal step0     : std_logic;
  signal step1     : std_logic;
  signal step2     : std_logic;

  component fifo_ic_got_TestController is
    port (
      Clock0  : in  std_logic;
      Clock1  : in  std_logic;
      Clock2  : in  std_logic;
      Reset   : in  std_logic;
      put0    : out std_logic;
      di0     : in  tDataWord;
      full0   : in  std_logic;
      got1    : out std_logic;
      do1     : in  tDataWord;
      valid1  : in  std_logic;
      put1    : out std_logic;
      di1     : in  tDataWord;
      full1   : in  std_logic;
      got2    : out std_logic;
      do2     : in  tDataWord;
      valid2  : in  std_logic;
      dat2    : in  tDataWord
    );
  end component;

begin
  -- Clock generation - three independent clocks
  Osvvm.ClockResetPkg.CreateClock(
    Clk    => Clock0,
    Period => TPERIOD_CLK0
  );

  Osvvm.ClockResetPkg.CreateClock(
    Clk    => Clock1,
    Period => TPERIOD_CLK1
  );

  Osvvm.ClockResetPkg.CreateClock(
    Clk    => Clock2,
    Period => TPERIOD_CLK2
  );

  -- Reset generation (use slowest clock for reset timing)
  Osvvm.ClockResetPkg.CreateReset(
    Reset       => Reset,
    ResetActive => '1',
    Clk         => Clock1,
    Period      => 3 * TPERIOD_CLK1,
    tpd         => 0 ns
  );

  ---------------------------------------------------------------------------
  -- Input Scrambler (clk0 domain) - generates write data
  ---------------------------------------------------------------------------
  step0 <= put0 and not full0;
  
  InputScrambler : entity PoC.comm_scramble
    generic map (
      GEN  => GEN,
      BITS => D_BITS
    )
    port map (
      clk  => Clock0,
      set  => Reset,
      din  => ORG,
      step => step0,
      mask => di0
    );

  ---------------------------------------------------------------------------
  -- First FIFO: clk0 -> clk1
  ---------------------------------------------------------------------------
  FIFO_0_1 : entity PoC.fifo_ic_got
    generic map (
      D_BITS         => D_BITS,
      MIN_DEPTH      => MIN_DEPTH,
      OUTPUT_REG     => OUTPUT_REG,
      ESTATE_WR_BITS => ESTATE_WR_BITS,
      FSTATE_RD_BITS => FSTATE_RD_BITS
    )
    port map (
      clk_wr    => Clock0,
      rst_wr    => Reset,
      put       => put0,
      din       => di0,
      full      => full0,
      estate_wr => open,
      clk_rd    => Clock1,
      rst_rd    => Reset,
      got       => got1,
      valid     => valid1,
      dout      => do1,
      fstate_rd => open
    );

  ---------------------------------------------------------------------------
  -- Intermediate Scrambler (clk1 domain) - for pass-through verification
  ---------------------------------------------------------------------------
  got1  <= valid1 and not full1;
  put1  <= got1;
  step1 <= put1;
  
  IntermediateScrambler : entity PoC.comm_scramble
    generic map (
      GEN  => GEN,
      BITS => D_BITS
    )
    port map (
      clk  => Clock1,
      set  => Reset,
      din  => ORG,
      step => step1,
      mask => di1
    );

  ---------------------------------------------------------------------------
  -- Second FIFO: clk1 -> clk2
  ---------------------------------------------------------------------------
  FIFO_1_2 : entity PoC.fifo_ic_got
    generic map (
      DATA_REG       => true,
      D_BITS         => D_BITS,
      MIN_DEPTH      => MIN_DEPTH,
      ESTATE_WR_BITS => ESTATE_WR_BITS,
      FSTATE_RD_BITS => FSTATE_RD_BITS
    )
    port map (
      clk_wr    => Clock1,
      rst_wr    => Reset,
      put       => put1,
      din       => di1,
      full      => full1,
      estate_wr => open,
      clk_rd    => Clock2,
      rst_rd    => Reset,
      got       => got2,
      valid     => valid2,
      dout      => do2,
      fstate_rd => open
    );

  ---------------------------------------------------------------------------
  -- Output Scrambler (clk2 domain) - for final verification
  ---------------------------------------------------------------------------
  OutputScrambler : entity PoC.comm_scramble
    generic map (
      GEN  => GEN,
      BITS => D_BITS
    )
    port map (
      clk  => Clock2,
      set  => Reset,
      din  => ORG,
      step => got2,
      mask => dat2
    );

  ---------------------------------------------------------------------------
  -- Test Controller
  ---------------------------------------------------------------------------
  TestCtrl : component fifo_ic_got_TestController
    port map (
      Clock0  => Clock0,
      Clock1  => Clock1,
      Clock2  => Clock2,
      Reset   => Reset,
      put0    => put0,
      di0     => di0,
      full0   => full0,
      got1    => got1,
      do1     => do1,
      valid1  => valid1,
      put1    => put1,
      di1     => di1,
      full1   => full1,
      got2    => got2,
      do2     => do2,
      valid2  => valid2,
      dat2    => dat2
    );

end architecture;
