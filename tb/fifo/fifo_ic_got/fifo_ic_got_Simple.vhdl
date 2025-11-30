-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:					Thomas B. Preusser
--                  Gustavo Martin
--
-- Architecture:		fifo_ic_got_Simple
--
-- Description:
-- -------------------------------------
-- Simple OSVVM test for fifo_ic_got (independent clocks FIFO)
-- Tests cross-clock domain data transfer with chain of two FIFOs
-- Uses OSVVM Scoreboard for data integrity verification
-- Uses OSVVM Functional Coverage for CDC operation coverage
--
-- Test scenario:
-- 1. Data is written to FIFO0 in clk0 domain
-- 2. Data passes through FIFO0 and is verified in clk1 domain
-- 3. Data is then passed to FIFO1 in clk1 domain
-- 4. Final data is verified in clk2 domain
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

architecture Simple of fifo_ic_got_TestController is
  -- Test synchronization
  signal TestDone    : integer_barrier := 1;
  signal WriterDone  : std_logic := '0';
  signal PassThruOK  : std_logic := '0';

  -- Alert/Log IDs
  constant TCID : AlertLogIDType := NewID("FifoIcGotTest");

  -- Scoreboard for FIFO data verification
  shared variable FifoSB : osvvm.ScoreboardPkg_slv.ScoreboardPType;

  -- Functional Coverage
  shared variable PhaseCov    : CovPType;  -- Test phase coverage
  shared variable TransferCov : CovPType;  -- Transfer pattern coverage
  shared variable StateCov    : CovPType;  -- Full/Valid state coverage

begin
  ----------------------------------------------------------------------------
  -- Control Process - manages test lifecycle
  ----------------------------------------------------------------------------
  ControlProc : process
    constant ProcID  : AlertLogIDType := NewID("ControlProc", TCID);
    constant TIMEOUT : time := 500 ms;
  begin
    SetTestName("fifo_ic_got_Simple");

    SetLogEnable(PASSED, FALSE);
    SetLogEnable(INFO,   TRUE);
    SetLogEnable(DEBUG,  FALSE);
    wait for 0 ns; wait for 0 ns;

    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    -- Initialize Scoreboard
    -- Initialize Phase Coverage
    PhaseCov.AddBins("Slow_Input",  GenBin(1));  -- Slow input, no back-pressure
    PhaseCov.AddBins("Fast_Input",  GenBin(2));  -- Fast input, possible back-pressure
    PhaseCov.AddBins("Drain",       GenBin(3));  -- Let FIFOs drain
    PhaseCov.SetName("PhaseCoverage");

    -- Initialize Transfer Coverage
    TransferCov.AddBins("Transfer_Active",  GenBin(1));  -- Data being transferred
    TransferCov.AddBins("Transfer_Stalled", GenBin(0));  -- Transfer stalled (full or no valid)
    TransferCov.SetName("TransferCoverage");

    -- Initialize State Coverage (full, valid combinations)
    StateCov.AddCross("State",
      GenBin(0, 1),   -- full
      GenBin(0, 1)    -- valid
    );
    StateCov.SetName("StateCoverage");

    wait until Reset = '0';
    ClearAlerts;

    WaitForBarrier(TestDone, TIMEOUT);
    AlertIf(ProcID, now >= TIMEOUT, "Test finished due to timeout");
    AlertIf(ProcID, GetAffirmCount < 1, "Test is not Self-Checking");

    -- Report Coverage results
    Log(ProcID, "=== Coverage Reports ===", ALWAYS);
    PhaseCov.WriteBin;
    TransferCov.WriteBin;
    StateCov.WriteBin;

    EndOfTestReports(ReportAll => TRUE);
    std.env.stop;
  end process;

  ----------------------------------------------------------------------------
  -- Writer Process (clk0 domain) - generates input data
  ----------------------------------------------------------------------------
  WriterProc : process
    constant ProcID   : AlertLogIDType := NewID("WriterProc", TCID);
    variable cnt      : natural := 0;
    constant TOTAL    : natural := 4 * MIN_DEPTH;
  begin
    put0 <= '0';
    WriterDone <= '0';
    wait until Reset = '0';
    wait until rising_edge(Clock0);

    Log(ProcID, "Starting write sequence: " & integer'image(TOTAL) & " words", INFO);

    ---------------------------------------------------------------------------
    -- Phase 1: Slow Input (wait for FIFO1 to be empty before writing)
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 1: Slow input", INFO);
    while cnt < 2*MIN_DEPTH loop
      wait until falling_edge(Clock0);
      if full0 = '0' and valid1 = '0' then
        put0 <= '1';
        PhaseCov.ICover(1);
        StateCov.ICover((0, 0));  -- not full, not valid
        cnt := cnt + 1;
      else
        put0 <= '0';
        if full0 = '1' then
          StateCov.ICover((1, to_integer(unsigned'('0' & valid1))));
        else
          StateCov.ICover((0, to_integer(unsigned'('0' & valid1))));
        end if;
      end if;
    end loop;

    ---------------------------------------------------------------------------
    -- Phase 2: Fast Input (write as fast as possible)
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 2: Fast input", INFO);
    while cnt < TOTAL loop
      wait until falling_edge(Clock0);
      if full0 = '0' then
        put0 <= '1';
        PhaseCov.ICover(2);
        TransferCov.ICover(1);
        cnt := cnt + 1;
      else
        put0 <= '0';
        TransferCov.ICover(0);
        StateCov.ICover((1, to_integer(unsigned'('0' & valid1))));
      end if;
    end loop;

    ---------------------------------------------------------------------------
    -- Phase 3: Drain
    ---------------------------------------------------------------------------
    wait until falling_edge(Clock0);
    put0 <= '0';
    PhaseCov.ICover(3);
    WriterDone <= '1';

    Log(ProcID, "Writer completed: " & integer'image(cnt) & " words written", INFO);
    WaitForBarrier(TestDone);
    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Pass-through Checker (clk1 domain) - verifies intermediate data
  ----------------------------------------------------------------------------
  PassThruChecker : process
    constant ProcID : AlertLogIDType := NewID("PassThruChecker", TCID);
    variable cnt    : natural := 0;
    constant TOTAL  : natural := 4 * MIN_DEPTH;
  begin
    PassThruOK <= '0';
    wait until Reset = '0';

    Log(ProcID, "Starting pass-through verification", INFO);

    while cnt < TOTAL loop
      wait until rising_edge(Clock1);
      
      -- Verify data matches scrambler output when transfer occurs
      if put1 = '1' then
        AffirmIf(ProcID,
          (Reset = '1') or (do1 = di1),
          "Pass-through mismatch in clk1 at count " & integer'image(cnt) &
          ": FIFO1 out = 0x" & to_hstring(do1) &
          ", Scrambler = 0x" & to_hstring(di1)
        );
        cnt := cnt + 1;
        TransferCov.ICover(1);
      else
        TransferCov.ICover(0);
      end if;
    end loop;

    PassThruOK <= '1';
    Log(ProcID, "Pass-through verification completed: " & integer'image(cnt) & " words verified", INFO);
    WaitForBarrier(TestDone);
    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Reader Process (clk2 domain) - final data verification
  ----------------------------------------------------------------------------
  ReaderProc : process
    constant ProcID : AlertLogIDType := NewID("ReaderProc", TCID);
    variable cnt    : natural := 0;
    variable del    : natural := 0;
    constant TOTAL  : natural := 4 * MIN_DEPTH;
  begin
    got2 <= '0';
    wait until Reset = '0';

    Log(ProcID, "Starting final verification", INFO);

    while cnt < TOTAL loop
      wait until rising_edge(Clock2);
      got2 <= '0';
      
      if valid2 = '1' then
        del := del + 1;
        -- Delay every 3rd read to create back-pressure
        if del = 3 then
          got2 <= '1';
          
          -- Verify data matches output scrambler
          AffirmIf(ProcID,
            dat2 = do2,
            "Final output mismatch in clk2 at count " & integer'image(cnt) &
            ": FIFO2 out = 0x" & to_hstring(do2) &
            ", Expected = 0x" & to_hstring(dat2)
          );
          
          cnt := cnt + 1;
          del := 0;
          TransferCov.ICover(1);
        else
          TransferCov.ICover(0);
        end if;
      end if;
    end loop;

    got2 <= '0';
    Log(ProcID, "Final verification completed: " & integer'image(cnt) & " words verified", INFO);
    WaitForBarrier(TestDone);
    wait;
  end process;

end architecture;

-- Configuration for Simple test
configuration fifo_ic_got_Simple of fifo_ic_got_TestHarness is
  for TestHarness
    for TestCtrl : fifo_ic_got_TestController
      use entity work.fifo_ic_got_TestController(Simple);
    end for;
  end for;
end configuration;
