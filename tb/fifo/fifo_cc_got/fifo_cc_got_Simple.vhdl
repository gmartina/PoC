-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Thomas B. Preusser
--                  Gustavo Martin
--
-- Architecture:    fifo_cc_got_Simple
--
-- Description:
-- -------------------------------------
-- Simple OSVVM test for fifo_cc_got using Verification Components
-- Uses Transaction interface to communicate with VCs:
--   - Send/SendBurst for writes via TxRec
--   - Check/CheckBurst for reads/verification via RxRec
--
-- Tests sequential writes, burst transfers, and random patterns
-- Uses OSVVM FifoFillPkg for burst data generation
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

architecture Simple of fifo_cc_got_TestController is
  -- Test synchronization
  signal TestDone   : integer_barrier := 1;
  signal Phase1Done : integer_barrier := 1;
  signal Phase2Done : integer_barrier := 1;

  -- Alert/Log IDs
  constant TCID : AlertLogIDType := NewID("FifoCcGotSimple_" & ConfigToString(CONFIG_INDEX));

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
    SetTestName("fifo_cc_got_Simple");

    SetLogEnable(PASSED, FALSE);
    SetLogEnable(INFO,   TRUE);
    SetLogEnable(DEBUG,  FALSE);
    wait for 0 ns; wait for 0 ns;

    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    -- Initialize Burst FIFOs (aliases point to TxRec.BurstFifo and RxRec.BurstFifo)
    TxBurstFifo <= NewID("TxBurstFifo", TCID);
    RxBurstFifo <= NewID("RxBurstFifo", TCID);

    -- Initialize Functional Coverage
    FifoCov.AddBins("FIFO_Empty",    GenBin(0));
    FifoCov.AddBins("FIFO_Quarter",  GenBin(1, MIN_DEPTH/4));
    FifoCov.AddBins("FIFO_Half",     GenBin(MIN_DEPTH/4 + 1, MIN_DEPTH/2));
    FifoCov.AddBins("FIFO_ThreeQ",   GenBin(MIN_DEPTH/2 + 1, 3*MIN_DEPTH/4));
    FifoCov.AddBins("FIFO_Full",     GenBin(3*MIN_DEPTH/4 + 1, MIN_DEPTH));
    FifoCov.SetName("FifoCoverage_" & ConfigToString(CONFIG_INDEX));

    wait until nReset = '1';
    ClearAlerts;

    WaitForBarrier(TestDone, TIMEOUT);
    AlertIf(ProcID, now >= TIMEOUT, "Test finished due to timeout");
    AlertIf(ProcID, GetAffirmCount < 1, "Test is not Self-Checking");

    -- Report Coverage results
    FifoCov.WriteBin;

    EndOfTestReports(ReportAll => TRUE);
    std.env.stop;
  end process;

  ----------------------------------------------------------------------------
  -- Writer Process - uses Transaction interface to send data via TxRec
  ----------------------------------------------------------------------------
  WriterProc : process
    constant ProcID : AlertLogIDType := NewID("WriterProc", TCID);
  begin
    wait until nReset = '1';
    WaitForClock(TxRec, 2);
    
    ---------------------------------------------------------------------------
    -- Phase 1: Sequential single-word sends (0 to 63)
    -- Uses Send() transaction for each word
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 1: Sequential single-word writes via Send()", INFO);
    for i in 0 to 63 loop
      Send(TxRec, std_logic_vector(to_unsigned(i, D_BITS)));
    end loop;
    
    -- Wait for reader to complete Phase 1
    WaitForBarrier(Phase1Done);
    
    ---------------------------------------------------------------------------
    -- Phase 2: Burst writes using SendBurst (64 to 191)
    -- Uses PushBurstIncrement to fill TxBurstFifo, then SendBurst
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 2: Burst writes via SendBurst()", INFO);
    
    -- Fill TxBurstFifo with burst data (alias points to TxRec.BurstFifo)
    PushBurstIncrement(TxBurstFifo, 64, 128, D_BITS);
    
    -- Send entire burst through transaction interface
    SendBurst(TxRec, 128);
    
    -- Wait for reader to complete Phase 2
    WaitForBarrier(Phase2Done);
    
    ---------------------------------------------------------------------------
    -- Phase 3: Random pattern writes (192 to 255)
    -- Uses PushBurstRandom for variety
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 3: Random pattern writes via SendBurst()", INFO);
    
    -- Fill TxBurstFifo with random data (alias points to TxRec.BurstFifo)
    PushBurstRandom(TxBurstFifo, 192, 64, D_BITS);
    
    -- Send burst
    SendBurst(TxRec, 64);

    Log(ProcID, "Writer complete - 256 words sent", INFO);
    WaitForBarrier(TestDone);
    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Reader Process - uses Transaction interface to check data via RxRec
  ----------------------------------------------------------------------------
  ReaderProc : process
    constant ProcID : AlertLogIDType := NewID("ReaderProc", TCID);
    variable ReadData : std_logic_vector(D_BITS-1 downto 0);
  begin
    wait until nReset = '1';
    WaitForClock(RxRec, 2);

    ---------------------------------------------------------------------------
    -- Phase 1: Check sequential data (0 to 63)
    -- Uses Check() transaction which reads and verifies expected value
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 1: Verifying sequential data via Check()", INFO);
    for i in 0 to 63 loop
      Check(RxRec, std_logic_vector(to_unsigned(i, D_BITS)));
    end loop;
    
    -- Signal writer that Phase 1 read is complete
    WaitForBarrier(Phase1Done);
    
    ---------------------------------------------------------------------------
    -- Phase 2: Check burst data using CheckBurst (64 to 191)
    -- Uses PushBurstIncrement to fill RxBurstFifo with expected values
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 2: Verifying burst data via CheckBurst()", INFO);
    
    -- Prepare expected values in RxBurstFifo (alias points to RxRec.BurstFifo)
    PushBurstIncrement(RxBurstFifo, 64, 128, D_BITS);
    
    -- Check entire burst
    CheckBurst(RxRec, 128);
    
    -- Signal writer that Phase 2 read is complete
    WaitForBarrier(Phase2Done);
    
    ---------------------------------------------------------------------------
    -- Phase 3: Check random data (192 to 255)
    -- Uses same seed as writer for matching random sequence
    ---------------------------------------------------------------------------
    Log(ProcID, "Phase 3: Verifying random data via CheckBurst()", INFO);
    
    -- Prepare expected values (same seed as writer, alias points to RxRec.BurstFifo)
    PushBurstRandom(RxBurstFifo, 192, 64, D_BITS);
    
    -- Check burst
    CheckBurst(RxRec, 64);

    Log(ProcID, "Reader complete - 256 words verified", INFO);
    
    -- Signal completion
    WaitForBarrier(TestDone);
    wait;
  end process;

end architecture;

-- Configuration for Simple test
configuration fifo_cc_got_Simple of fifo_cc_got_TestHarness is
  for TestHarness
    for TestCtrl : fifo_cc_got_TestController
      use entity work.fifo_cc_got_TestController(Simple);
    end for;
  end for;
end configuration;
