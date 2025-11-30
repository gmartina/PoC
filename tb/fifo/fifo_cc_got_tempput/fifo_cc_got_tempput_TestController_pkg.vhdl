-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:					Thomas B. Preusser
--                  Gustavo Martin
--
-- Package:					fifo_cc_got_tempput_TestController_pkg
--
-- Description:
-- -------------------------------------
-- Test controller package for fifo_cc_got_tempput OSVVM testbench
-- FIFO with Common Clock and temporary put with commit/rollback
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

package fifo_cc_got_tempput_TestController_pkg is

  -- FIFO Configuration Constants
  constant D_BITS         : positive := 8;
  constant MIN_DEPTH      : positive := 8;
  constant ESTATE_WR_BITS : natural  := 2;
  constant FSTATE_RD_BITS : natural  := 2;

  -- Test specification strings (from original testbench)
  -- Input spec: ' '=wait, 'p'=put, 'c'=commit, 'C'=put+commit, 'r'=rollback, 'R'=put+rollback
  constant ISPEC : string := "C C Cccccpppp pppp c ccc pp         Cppppp ppp rp RpC";
  -- Output spec: ' '=wait, 'g'=got (expect match), 'G'=got (expect mismatch after rollback)
  constant OSPEC : string := "ggg                      gggggggg  ggg G           G";

  -- Sequence Generator parameters (LFSR)
  constant GEN : bit_vector       := "100110001";
  constant ORG : std_logic_vector := "00000001";

  -- Configuration index type
  type tConfigIndex is range 0 to 7;
  
  -- Helper functions
  function GetDataReg(idx : tConfigIndex) return boolean;
  function GetStateReg(idx : tConfigIndex) return boolean;
  function GetOutputReg(idx : tConfigIndex) return boolean;
  function ConfigToString(idx : tConfigIndex) return string;

  -- Data word type
  subtype tDataWord is std_logic_vector(D_BITS-1 downto 0);

end package;

package body fifo_cc_got_tempput_TestController_pkg is

  function GetDataReg(idx : tConfigIndex) return boolean is
  begin
    return (idx mod 2) > 0;
  end function;

  function GetStateReg(idx : tConfigIndex) return boolean is
  begin
    return (idx mod 4) > 1;
  end function;

  function GetOutputReg(idx : tConfigIndex) return boolean is
  begin
    return (idx mod 8) > 3;
  end function;

  function ConfigToString(idx : tConfigIndex) return string is
  begin
    return "DATA_REG=" & boolean'image(GetDataReg(idx)) &
           " STATE_REG=" & boolean'image(GetStateReg(idx)) &
           " OUTPUT_REG=" & boolean'image(GetOutputReg(idx));
  end function;

end package body;
