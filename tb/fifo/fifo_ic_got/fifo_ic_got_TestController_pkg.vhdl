-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:					Thomas B. Preusser
--                  Gustavo Martin
--
-- Package:					fifo_ic_got_TestController_pkg
--
-- Description:
-- -------------------------------------
-- Test controller package for fifo_ic_got OSVVM testbench
-- FIFO with independent clocks (cross-clock domain FIFO)
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

package fifo_ic_got_TestController_pkg is

  -- FIFO Configuration Constants
  constant D_BITS         : positive := 9;
  constant MIN_DEPTH      : positive := 8;
  constant OUTPUT_REG     : boolean  := true;
  constant ESTATE_WR_BITS : natural  := 2;
  constant FSTATE_RD_BITS : natural  := 2;

  -- Sequence Generator parameters (LFSR)
  constant GEN : bit_vector       := "100110001";
  constant ORG : std_logic_vector := "00000001";

  -- Data word type
  subtype tDataWord is std_logic_vector(D_BITS-1 downto 0);

end package;

package body fifo_ic_got_TestController_pkg is
end package body;
