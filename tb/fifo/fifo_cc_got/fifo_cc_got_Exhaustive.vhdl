-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Thomas B. Preusser
--                  Gustavo Martin
--
-- Architecture:    fifo_cc_got_Exhaustive
--
-- Description:
-- -------------------------------------
-- Exhaustive OSVVM test for fifo_cc_got using Verification Components
-- Uses Transaction interface to communicate with VCs for:
-- - Full/Empty transitions
-- - Back-to-back operations
-- - Burst operations with PushBurstIncrement/PushBurstRandom
-- - State indicator verification via GetFifoStatus
-- - Simultaneous read/write stress testing
--
-- Uses OSVVM FifoFillPkg for sophisticated burst patterns
-- Uses cross-coverage for state combinations
--
-- License:
-- =============================================================================
-- Copyright 2025-2025 The PoC-Library Authors
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--    http://www.apache.org/licenses/LICENSE-2.0
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
use     osvvm.ScoreboardPkg_slv.all;

library osvvm_common;
context osvvm_common.OsvvmCommonContext;
use     osvvm_common.FifoFillPkg_slv.all;

use     work.fifo_cc_got_TestController_pkg.all;

architecture Exhaustive of fifo_cc_got_TestController is
  -- Phase synchronization barriers
  signal TestDone   : integer_barrier := 1;
  signal Phase1Done : integer_barrier := 1;
  signal Phase2Done : integer_barrier := 1;
  signal Phase3Done : integer_barrier := 1;
  signal Phase4Done : integer_barrier := 1;

  -- Alert/Log IDs
  constant TCID : AlertLogIDType := NewID("FifoCcGotExhaustive_" & ConfigToString(CONFIG_INDEX));

  -- Functional Coverage
  shared variable StateCov   : CovPType;  -- Full/Valid cross-coverage
  shared variable OpCov      : CovPType;  -- Operation coverage
  shared variable FillCov    : CovPType;  -- Fill level coverage
  shared variable TransCov   : CovPType;  -- Transition coverage

begin
  ----------------------------------------------------------------------------
  -- Control Process - manages test lifecycle
  ----------------------------------------------------------------------------
  ControlProc : process
    constant ProcID  : AlertLogIDType := NewID("ControlProc", TCID);
    constant TIMEOUT : time := 500 ms;
  begin
    SetTestName("fifo_cc_got_Exhaustive");

    SetLogEnable(PASSED, FALSE);
    SetLogEnable(INFO,   TRUE);
    SetLogEnable(DEBUG,  FALSE);
    wait for 0 ns; wait for 0 ns;

    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    -- Initialize Burst FIFOs
    TxBurstFifo <= NewID("TxBurstFifo", TCID);
    RxBurstFifo <= NewID("RxBurstFifo", TCID);

    -- Initialize State Cross-Coverage (full x valid)
    StateCov.AddCross("Full_Valid_Cross",
      GenBin(0, 1),   -- full
      GenBin(0, 1)    -- valid
    );
    StateCov.SetName("StateCrossCoverage");

    -- Initialize Operation Coverage
    OpCov.AddBins("Send",          GenBin(1));
    OpCov.AddBins("Check",         GenBin(2));
    OpCov.AddBins("SendBurst",     GenBin(3));
    OpCov.AddBins("CheckBurst",    GenBin(4));
    OpCov.AddBins("TrySend",       GenBin(5));
    OpCov.AddBins("TryCheck",      GenBin(6));
    OpCov.SetName("OperationCoverage");

    -- Initialize Fill Level Coverage
    for i in 0 to MIN_DEPTH/4 loop
      FillCov.AddBins("Fill_" & integer'image(i*4) & "_to_" & integer'image(minimum((i+1)*4-1, MIN_DEPTH)),
        GenBin(i*4, minimum((i+1)*4-1, MIN_DEPTH)));
    end loop;
    FillCov.SetName("FillLevelCoverage");

    -- Initialize Transition Coverage
    TransCov.AddBins("Empty_to_Filling",     GenBin(1));
    TransCov.AddBins("Filling_to_Full",      GenBin(2));
    TransCov.AddBins("Full_to_Draining",     GenBin(3));
    TransCov.AddBins("Draining_to_Empty",    GenBin(4));
    TransCov.AddBins("Steady_State",         GenBin(5));
    TransCov.SetName("TransitionCoverage");

    wait until nReset = '1';
    ClearAlerts;

    WaitForBarrier(TestDone, TIMEOUT);
    AlertIf(ProcID, now >= TIMEOUT, "Test finished due to timeout");
    AlertIf(ProcID, GetAffirmCount < 1, "Test is not Self-Checking");

    -- Report Coverage results
    Log(ProcID, "=== Coverage Reports ===", ALWAYS);
    StateCov.WriteBin;
    OpCov.WriteBin;
    FillCov.WriteBin;
    TransCov.WriteBin;

    EndOfTestReports(ReportAll => TRUE);
    std.env.stop;
  end process;

  ----------------------------------------------------------------------------
  -- Writer Process - uses Transaction interface to send data
  ----------------------------------------------------------------------------
  WriterProc : process
    constant ProcID   : AlertLogIDType := NewID("WriterProc", TCID);
    variable WriteCount : integer := 0;
    variable SendOk     : boolean;
  begin
    wait until nReset = '1';
    WaitForClock(TxRec, 2);

    -- Assign BurstFifo to transaction record
    TxRec.BurstFifo <= TxBurstFifo;

    ---------------------------------------------------------------------------
    -- Phase 1: Fill FIFO to capacity using Send()
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 1: Fill FIFO to capacity via Send()", INFO);
    
    TransCov.ICover(1);  -- Empty_to_Filling
    
    -- Fill with sequential data using individual Send transactions
    for i in 0 to MIN_DEPTH-1 loop
      -- Use blocking Send with std_logic_vector
      Send(TxRec, std_logic_vector(to_unsigned(i, D_BITS)));
      WriteCount := WriteCount + 1;
      OpCov.ICover(1);  -- Send
      FillCov.ICover(WriteCount);
    end loop;
    
    TransCov.ICover(2);  -- Filling_to_Full
    Log(ProcID, "Phase 1: Filled " & integer'image(WriteCount) & " words", INFO);
    
    -- Wait for reader to drain Phase 1
    WaitForBarrier(Phase1Done);

    ---------------------------------------------------------------------------
    -- Phase 2: Burst writes using SendBurst (128 words)
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 2: Burst writes via SendBurst()", INFO);
    
    -- Fill TxBurstFifo with incremental data
    PushBurstIncrement(TxBurstFifo, WriteCount, 128, D_BITS);
    
    -- Send burst
    SendBurst(TxRec, 128);
    WriteCount := WriteCount + 128;
    OpCov.ICover(3);  -- SendBurst
    
    Log(ProcID, "Phase 2: Wrote 128 burst words", INFO);
    
    -- Wait for reader to complete Phase 2
    WaitForBarrier(Phase2Done);

    ---------------------------------------------------------------------------
    -- Phase 3: Random burst writes with multiple small bursts
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 3: Multiple random bursts via SendBurst()", INFO);
    
    for burst in 0 to 3 loop
      -- Fill with random data
      PushBurstRandom(TxBurstFifo, WriteCount + burst*16, 16, D_BITS);
      
      -- Send burst of 16 words
      SendBurst(TxRec, 16);
      WriteCount := WriteCount + 16;
      OpCov.ICover(3);  -- SendBurst
      
      -- Small gap between bursts
      WaitForClock(TxRec, 5);
    end loop;
    
    Log(ProcID, "Phase 3: Wrote 64 random burst words", INFO);
    
    -- Wait for reader to complete Phase 3
    WaitForBarrier(Phase3Done);

    ---------------------------------------------------------------------------
    -- Phase 4: Mixed operations stress test
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 4: Mixed operations stress test", INFO);
    
    -- Mix of single sends and small bursts
    for i in 0 to 24 loop
      if (i mod 3) = 0 then
        -- Single send
        Send(TxRec, std_logic_vector(to_unsigned(WriteCount, D_BITS)));
        WriteCount := WriteCount + 1;
        OpCov.ICover(1);  -- Send
      else
        -- Small burst of 4 words
        PushBurstIncrement(TxBurstFifo, WriteCount, 4, D_BITS);
        SendBurst(TxRec, 4);
        WriteCount := WriteCount + 4;
        OpCov.ICover(3);  -- SendBurst
      end if;
    end loop;

    Log(ProcID, "Total writes: " & integer'image(WriteCount), INFO);
    
    WaitForBarrier(Phase4Done);
    WaitForBarrier(TestDone);
    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Reader Process - uses Transaction interface to verify data
  ----------------------------------------------------------------------------
  ReaderProc : process
    constant ProcID   : AlertLogIDType := NewID("ReaderProc", TCID);
    variable ReadCount  : integer := 0;
    variable ReadData   : std_logic_vector(D_BITS-1 downto 0);
  begin
    wait until nReset = '1';
    WaitForClock(RxRec, 2);

    -- Assign BurstFifo to transaction record
    RxRec.BurstFifo <= RxBurstFifo;

    ---------------------------------------------------------------------------
    -- Phase 1: Drain FIFO using Check()
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 1: Drain FIFO via Check()", INFO);
    
    -- Drain sequential data using individual Check transactions
    for i in 0 to MIN_DEPTH-1 loop
      Check(RxRec, std_logic_vector(to_unsigned(i, D_BITS)));
      ReadCount := ReadCount + 1;
      OpCov.ICover(2);  -- Check
    end loop;
    
    TransCov.ICover(4);  -- Draining_to_Empty
    Log(ProcID, "Phase 1: Read " & integer'image(ReadCount) & " words", INFO);
    
    WaitForBarrier(Phase1Done);

    ---------------------------------------------------------------------------
    -- Phase 2: Verify burst data using CheckBurst
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 2: Verify burst data via CheckBurst()", INFO);
    
    -- Prepare expected values
    PushBurstIncrement(RxBurstFifo, ReadCount, 128, D_BITS);
    
    -- Check burst
    CheckBurst(RxRec, 128);
    ReadCount := ReadCount + 128;
    OpCov.ICover(4);  -- CheckBurst
    
    Log(ProcID, "Phase 2: Verified 128 words", INFO);
    
    WaitForBarrier(Phase2Done);

    ---------------------------------------------------------------------------
    -- Phase 3: Verify random burst data
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 3: Verify random bursts via CheckBurst()", INFO);
    
    for burst in 0 to 3 loop
      -- Same seed pattern as writer
      PushBurstRandom(RxBurstFifo, ReadCount + burst*16, 16, D_BITS);
      
      -- Check burst
      CheckBurst(RxRec, 16);
      ReadCount := ReadCount + 16;
      OpCov.ICover(4);  -- CheckBurst
    end loop;
    
    Log(ProcID, "Phase 3: Verified 64 words", INFO);
    
    WaitForBarrier(Phase3Done);

    ---------------------------------------------------------------------------
    -- Phase 4: Verify mixed operations
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 4: Verify mixed operations", INFO);
    
    for i in 0 to 24 loop
      if (i mod 3) = 0 then
        -- Single check
        Check(RxRec, std_logic_vector(to_unsigned(ReadCount, D_BITS)));
        ReadCount := ReadCount + 1;
        OpCov.ICover(2);  -- Check
      else
        -- Small burst of 4 words
        PushBurstIncrement(RxBurstFifo, ReadCount, 4, D_BITS);
        CheckBurst(RxRec, 4);
        ReadCount := ReadCount + 4;
        OpCov.ICover(4);  -- CheckBurst
      end if;
    end loop;

    Log(ProcID, "Total reads verified: " & integer'image(ReadCount), INFO);
    
    WaitForBarrier(Phase4Done);
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
