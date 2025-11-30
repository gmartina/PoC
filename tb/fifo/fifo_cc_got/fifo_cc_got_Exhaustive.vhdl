-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:					Thomas B. Preusser
--                  Gustavo Martin
--
-- Architecture:		fifo_cc_got_Exhaustive
--
-- Description:
-- -------------------------------------
-- Exhaustive OSVVM test for fifo_cc_got
-- Tests all FIFO operations with extensive coverage:
-- - Full/Empty transitions
-- - Back-to-back operations
-- - Random patterns
-- - State indicator verification
-- Uses OSVVM Scoreboard and Functional Coverage
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

architecture Exhaustive of fifo_cc_got_TestController is
  -- Test synchronization
  signal TestDone     : integer_barrier := 1;
  signal WriterDone   : std_logic := '0';

  -- Alert/Log IDs
  constant TCID : AlertLogIDType := NewID("FifoCcGotExhaustive_" & ConfigToString(CONFIG_INDEX));

  -- Scoreboard for FIFO data verification
  shared variable FifoSB : osvvm.ScoreboardPkg_slv.ScoreboardPType;

  -- Functional Coverage
  shared variable StateCov   : CovPType;  -- Full/Empty/Valid state coverage
  shared variable OpCov      : CovPType;  -- Operation coverage (put, got, simultaneous)
  shared variable FillCov    : CovPType;  -- Fill level coverage
  shared variable EstateCov  : CovPType;  -- Empty state bits coverage
  shared variable FstateCov  : CovPType;  -- Full state bits coverage

begin
  ----------------------------------------------------------------------------
  -- Control Process - manages test lifecycle
  ----------------------------------------------------------------------------
  ControlProc : process
    constant ProcID  : AlertLogIDType := NewID("ControlProc", TCID);
    constant TIMEOUT : time := 500 ms;
  begin
    SetTestName("fifo_cc_got_Exhaustive_Config" & integer'image(tConfigIndex'pos(CONFIG_INDEX)));

    SetLogEnable(PASSED, FALSE);
    SetLogEnable(INFO,   TRUE);
    SetLogEnable(DEBUG,  FALSE);
    wait for 0 ns; wait for 0 ns;

    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    -- Initialize State Coverage (full, valid, empty combinations)
    StateCov.AddCross("State_Full_Valid",
      GenBin(0, 1),   -- full
      GenBin(0, 1)    -- valid
    );
    StateCov.SetName("StateCoverage");

    -- Initialize Operation Coverage
    OpCov.AddBins("Put_Only",         GenBin(1));  -- put without got
    OpCov.AddBins("Got_Only",         GenBin(2));  -- got without put
    OpCov.AddBins("Put_Got_Simul",    GenBin(3));  -- simultaneous put and got
    OpCov.AddBins("Idle",             GenBin(0));  -- no operation
    OpCov.SetName("OperationCoverage");

    -- Initialize Fill Level Coverage (bins of 4)
    for i in 0 to MIN_DEPTH/4 loop
      FillCov.AddBins("Fill_" & integer'image(i*4) & "_to_" & integer'image((i+1)*4-1),
        GenBin(i*4, (i+1)*4-1));
    end loop;
    FillCov.SetName("FillLevelCoverage");

    -- Initialize Estate (empty state) Coverage
    for i in 0 to 2**ESTATE_WR_BITS-1 loop
      EstateCov.AddBins("Estate_" & integer'image(i), GenBin(i));
    end loop;
    EstateCov.SetName("EstateWrCoverage");

    -- Initialize Fstate (full state) Coverage
    for i in 0 to 2**FSTATE_RD_BITS-1 loop
      FstateCov.AddBins("Fstate_" & integer'image(i), GenBin(i));
    end loop;
    FstateCov.SetName("FstateRdCoverage");

    wait until Reset = '0';
    ClearAlerts;

    WaitForBarrier(TestDone, TIMEOUT);
    AlertIf(ProcID, now >= TIMEOUT, "Test finished due to timeout");
    AlertIf(ProcID, GetAffirmCount < 1, "Test is not Self-Checking");

    -- Report Coverage results
    Log(ProcID, "=== Coverage Reports ===", ALWAYS);
    StateCov.WriteBin;
    OpCov.WriteBin;
    FillCov.WriteBin;
    EstateCov.WriteBin;
    FstateCov.WriteBin;

    EndOfTestReports(ReportAll => TRUE);
    std.env.stop;
  end process;

  ----------------------------------------------------------------------------
  -- Writer Process - generates data patterns and writes to FIFO
  ----------------------------------------------------------------------------
  WriterProc : process
    constant ProcID   : AlertLogIDType := NewID("WriterProc", TCID);
    variable DataVal  : unsigned(D_BITS-1 downto 0);
    variable RandGen  : RandomPType;
    variable OpCode   : integer;
  begin
    put <= '0';
    din <= (others => '-');
    WriterDone <= '0';
    wait until Reset = '0';
    WaitForClock(Clock);

    RandGen.InitSeed(tConfigIndex'pos(CONFIG_INDEX) + 123);

    ---------------------------------------------------------------------------
    -- Test Phase 1: Fill to full, verify full flag
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 1: Fill FIFO to capacity", INFO);
    DataVal := (others => '0');
    
    while full = '0' loop
      din <= std_logic_vector(DataVal);
      put <= '1';
      FifoSB.Push(std_logic_vector(DataVal));
      
      -- Sample coverage
      OpCov.ICover(1);  -- Put only
      if full = '1' then
        StateCov.ICover((1, to_integer(unsigned'('0' & valid))));
      else
        StateCov.ICover((0, to_integer(unsigned'('0' & valid))));
      end if;
      EstateCov.ICover(to_integer(unsigned(estate_wr)));
      
      wait until rising_edge(Clock);
      DataVal := DataVal + 1;
    end loop;
    
    put <= '0';
    din <= (others => '-');
    
    -- Verify full flag is asserted
    AffirmIf(ProcID, full = '1', "FIFO should be full after fill");
    Log(ProcID, "FIFO filled with " & integer'image(to_integer(DataVal)) & " words", INFO);

    ---------------------------------------------------------------------------
    -- Test Phase 2: Wait for drain, then refill with random delays
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 2: Random write patterns", INFO);
    -- Wait for FIFO to drain completely
    wait until valid = '0';
    
    for i in 0 to 63 loop
      -- Random delay before write
      for d in 1 to RandGen.RandInt(0, 3) loop
        wait until rising_edge(Clock);
        OpCov.ICover(0);  -- Idle
      end loop;
      
      -- Write data
      din <= std_logic_vector(DataVal);
      put <= '1';
      FifoSB.Push(std_logic_vector(DataVal));
      OpCov.ICover(1);  -- Put only
      EstateCov.ICover(to_integer(unsigned(estate_wr)));
      
      wait until rising_edge(Clock) and full = '0';
      DataVal := DataVal + 1;
    end loop;
    
    put <= '0';
    din <= (others => '-');

    ---------------------------------------------------------------------------
    -- Test Phase 3: Burst writes
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 3: Burst write test", INFO);
    -- Wait for FIFO to drain completely
    wait until valid = '0';
    
    for burst in 0 to 3 loop
      -- Burst of writes
      for i in 0 to 7 loop
        din <= std_logic_vector(DataVal);
        put <= '1';
        FifoSB.Push(std_logic_vector(DataVal));
        OpCov.ICover(1);
        wait until rising_edge(Clock) and full = '0';
        DataVal := DataVal + 1;
      end loop;
      
      -- Gap between bursts
      put <= '0';
      for d in 1 to 10 loop
        wait until rising_edge(Clock);
        OpCov.ICover(0);
      end loop;
    end loop;

    put <= '0';
    din <= (others => '-');
    WriterDone <= '1';
    
    WaitForBarrier(TestDone);
    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Reader Process - reads data and verifies against scoreboard
  ----------------------------------------------------------------------------
  ReaderProc : process
    constant ProcID   : AlertLogIDType := NewID("ReaderProc", TCID);
    variable Expected : tDataWord;
    variable RandGen  : RandomPType;
  begin
    got <= '0';
    wait until Reset = '0';

    RandGen.InitSeed(tConfigIndex'pos(CONFIG_INDEX) + 456);

    -- Keep reading until writer is done and scoreboard is empty
    ReadLoop: while (WriterDone = '0') or (valid = '1') loop
      
      -- Wait for valid data at clock edge (data is stable after this)
      wait until rising_edge(Clock);
      
      if valid = '1' then
        -- Sample state coverage
        if full = '1' then
          StateCov.ICover((1, 1));
        else
          StateCov.ICover((0, 1));
        end if;
        FstateCov.ICover(to_integer(unsigned(fstate_rd)));
        
        -- Get expected value from scoreboard and verify
        if not FifoSB.Empty then
          Expected := FifoSB.Pop;
          
          AffirmIf(ProcID,
            dout = Expected,
            "Data mismatch: Got 0x" & to_hstring(dout) &
            ", Expected 0x" & to_hstring(Expected) &
            " [" & ConfigToString(CONFIG_INDEX) & "]"
          );
        end if;
        
        -- Assert got to acknowledge data
        got <= '1';
        OpCov.ICover(2);  -- Got only
        wait until rising_edge(Clock);
        got <= '0';
        
        -- Random delay between reads  
        for d in 1 to RandGen.RandInt(0, 2) loop
          wait until rising_edge(Clock);
        end loop;
      end if;
      
    end loop ReadLoop;

    -- Verify scoreboard is empty
    AffirmIf(ProcID, FifoSB.Empty, "Scoreboard should be empty at end of test");

    WaitForBarrier(TestDone);
    wait;
  end process;

end architecture;

-- Configuration for Exhaustive test
configuration fifo_cc_got_Exhaustive of fifo_cc_got_TestHarness is
  for TestHarness
    for TestCtrl : fifo_cc_got_TestController
      use entity work.fifo_cc_got_TestController(Exhaustive);
    end for;
  end for;
end configuration;
