-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:					Thomas B. Preusser
--                  Gustavo Martin
--
-- Entity:					fifo_ic_got_TestController
--
-- Description:
-- -------------------------------------
-- Test controller entity for fifo_ic_got OSVVM testbench
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

use     work.fifo_ic_got_TestController_pkg.all;

entity fifo_ic_got_TestController is
  port (
    -- Clock domains
    Clock0    : in  std_logic;  -- Write clock domain 0
    Clock1    : in  std_logic;  -- Transfer clock domain 1
    Clock2    : in  std_logic;  -- Read clock domain 2
    Reset     : in  std_logic;
    
    -- FIFO 0->1 Write interface (clk0 domain)
    put0      : out std_logic;
    di0       : in  tDataWord;  -- From scrambler
    full0     : in  std_logic;
    
    -- FIFO 0->1 Read interface (clk1 domain)
    got1      : out std_logic;
    do1       : in  tDataWord;
    valid1    : in  std_logic;
    
    -- FIFO 1->2 Write interface (clk1 domain)
    put1      : out std_logic;
    di1       : in  tDataWord;  -- From intermediate scrambler
    full1     : in  std_logic;
    
    -- FIFO 1->2 Read interface (clk2 domain)
    got2      : out std_logic;
    do2       : in  tDataWord;
    valid2    : in  std_logic;
    dat2      : in  tDataWord   -- From output scrambler
  );
end entity;
