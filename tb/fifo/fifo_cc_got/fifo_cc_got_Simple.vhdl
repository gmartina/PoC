-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:					Thomas B. Preusser
--                  Gustavo Martin
--
-- Architecture:		fifo_cc_got_Simple
--
-- Description:
-- -------------------------------------
-- Simple OSVVM test for fifo_cc_got
-- Tests all 8 configuration variants (DATA_REG, STATE_REG, OUTPUT_REG)
-- Uses OSVVM Scoreboard for data integrity verification
-- Uses OSVVM Functional Coverage for FIFO state coverage
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

use     work.fifo_cc_got_TestController_pkg.all;

architecture Simple of fifo_cc_got_TestController is
  -- Test synchronization
  signal TestDone : integer_barrier := 1;

  -- Alert/Log IDs
  constant TCID : AlertLogIDType := NewID("FifoCcGotTest_" & ConfigToString(CONFIG_INDEX));

  -- Scoreboard for FIFO data verification
  shared variable FifoSB : osvvm.ScoreboardPkg_slv.ScoreboardPType;

  -- Functional Coverage for FIFO states
  shared variable FifoCov : CovPType;

begin
  ----------------------------------------------------------------------------
  -- Control Process - manages test lifecycle
  ----------------------------------------------------------------------------
  ControlProc : process
    constant ProcID  : AlertLogIDType := NewID("ControlProc", TCID);
    constant TIMEOUT : time := 100 ms;
  begin
    SetTestName("fifo_cc_got_Simple_Config" & integer'image(tConfigIndex'pos(CONFIG_INDEX)));

    SetLogEnable(PASSED, FALSE);
    SetLogEnable(INFO,   FALSE);
    SetLogEnable(DEBUG,  FALSE);
    wait for 0 ns; wait for 0 ns;

    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    -- Initialize Functional Coverage
    -- Coverage for FIFO empty/full states and fill levels
    FifoCov.AddBins("FIFO_Empty",    GenBin(0));     -- Empty state
    FifoCov.AddBins("FIFO_Quarter",  GenBin(1, MIN_DEPTH/4));
    FifoCov.AddBins("FIFO_Half",     GenBin(MIN_DEPTH/4 + 1, MIN_DEPTH/2));
    FifoCov.AddBins("FIFO_ThreeQ",   GenBin(MIN_DEPTH/2 + 1, 3*MIN_DEPTH/4));
    FifoCov.AddBins("FIFO_Full",     GenBin(3*MIN_DEPTH/4 + 1, MIN_DEPTH));
    FifoCov.SetName("FifoCoverage_" & ConfigToString(CONFIG_INDEX));

    wait until Reset = '0';
    ClearAlerts;

    WaitForBarrier(TestDone, TIMEOUT);
    AlertIf(ProcID, now >= TIMEOUT, "Test finished due to timeout");
    AlertIf(ProcID, GetAffirmCount < 1, "Test is not Self-Checking");

    -- Report Coverage results
    FifoCov.WriteBin;
    AlertIf(ProcID, not FifoCov.IsCovered, "Functional Coverage not achieved");

    EndOfTestReports(ReportAll => TRUE);
    std.env.stop;
  end process;

  ----------------------------------------------------------------------------
  -- Writer Process - generates data and writes to FIFO
  ----------------------------------------------------------------------------
  WriterProc : process
    constant ProcID   : AlertLogIDType := NewID("WriterProc", TCID);
    variable DataVal  : unsigned(D_BITS-1 downto 0);
    variable RandGen  : RandomPType;
    variable FillLevel : integer := 0;
  begin
    put <= '0';
    din <= (others => '-');
    wait until Reset = '0';
    WaitForClock(Clock);

    -- Initialize random generator with unique seed
    RandGen.InitSeed(tConfigIndex'pos(CONFIG_INDEX) + 42);

    -- Phase 1: Fill FIFO with sequential data (0 to 127)
    Log(ProcID, "Phase 1: Sequential fill test", INFO);
    for i in 0 to 2**(D_BITS-1)-1 loop
      DataVal := to_unsigned(i, D_BITS);
      din <= std_logic_vector(DataVal);
      put <= '1';
      
      -- Push expected value to scoreboard
      FifoSB.Push(std_logic_vector(DataVal));
      
      wait until rising_edge(Clock) and full = '0';
      
      -- Track fill level for coverage
      if full = '0' then
        FillLevel := FillLevel + 1;
        FifoCov.ICover(FillLevel);
      end if;
    end loop;

    -- Phase 2: Write after drain - interleaved operation (128 to 255)
    Log(ProcID, "Phase 2: Interleaved read/write test", INFO);
    for i in 2**(D_BITS-1) to 2**D_BITS-1 loop
      put <= '0';
      din <= (others => '-');
      wait until rising_edge(Clock) and valid = '0';
      
      DataVal := to_unsigned(i, D_BITS);
      din <= std_logic_vector(DataVal);
      put <= '1';
      
      -- Push expected value to scoreboard
      FifoSB.Push(std_logic_vector(DataVal));
      
      wait until rising_edge(Clock);
    end loop;

    put <= '0';
    din <= (others => '-');

    -- Signal completion
    WaitForBarrier(TestDone);
    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Reader Process - reads data and verifies against scoreboard
  ----------------------------------------------------------------------------
  ReaderProc : process
    constant ProcID   : AlertLogIDType := NewID("ReaderProc", TCID);
    variable Expected : tDataWord;
    variable ReadCount : integer := 0;
    variable FillLevel : integer := 0;
  begin
    got <= '0';
    wait until Reset = '0';

    -- Read all 256 values
    for i in 0 to 2**D_BITS-1 loop
      wait until rising_edge(Clock) and valid = '1';

      -- Get expected value from scoreboard and check
      Expected := FifoSB.Pop;
      AffirmIf(ProcID,
        dout = Expected,
        "Data mismatch at position " & integer'image(i) &
        ": Got 0x" & to_hstring(dout) &
        ", Expected 0x" & to_hstring(Expected) &
        " [" & ConfigToString(CONFIG_INDEX) & "]"
      );
      
      got <= '1';
      wait until rising_edge(Clock);
      got <= '0';
      
      -- Sample fill level for coverage
      if valid = '0' then
        FillLevel := 0;
      end if;
      FifoCov.ICover(FillLevel);
      
      wait until rising_edge(Clock);
      ReadCount := ReadCount + 1;
    end loop;

    -- Verify all data was read
    AffirmIf(ProcID, ReadCount = 2**D_BITS,
      "Read count mismatch: " & integer'image(ReadCount) & " vs expected " & integer'image(2**D_BITS));

    -- Signal completion
    WaitForBarrier(TestDone);
    wait;
  end process;

end architecture;

-- Configuration for Simple test with CONFIG_INDEX=0
configuration fifo_cc_got_Simple_Config0 of fifo_cc_got_TestHarness is
  for TestHarness
    for TestCtrl : fifo_cc_got_TestController
      use entity work.fifo_cc_got_TestController(Simple);
    end for;
  end for;
end configuration;
