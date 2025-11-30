-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:					Thomas B. Preusser
--                  Gustavo Martin
--
-- Architecture:		fifo_cc_got_tempput_Simple
--
-- Description:
-- -------------------------------------
-- Simple OSVVM test for fifo_cc_got_tempput
-- Tests commit/rollback functionality using scripted sequences
-- Uses OSVVM Scoreboard for data integrity verification
-- Uses OSVVM Functional Coverage for operation and state coverage
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

use     work.fifo_cc_got_tempput_TestController_pkg.all;

architecture Simple of fifo_cc_got_tempput_TestController is
  -- Test synchronization
  signal TestDone : integer_barrier := 1;

  -- Alert/Log IDs
  constant TCID : AlertLogIDType := NewID("FifoTempPutTest_" & ConfigToString(CONFIG_INDEX));

  -- Scoreboard for committed FIFO data verification
  shared variable FifoSB : osvvm.ScoreboardPkg_slv.ScoreboardPType;

  -- Functional Coverage
  shared variable OpCov    : CovPType;  -- Operation coverage (put, commit, rollback combinations)
  shared variable StateCov : CovPType;  -- Full/Valid state coverage

begin
  ----------------------------------------------------------------------------
  -- Control Process - manages test lifecycle
  ----------------------------------------------------------------------------
  ControlProc : process
    constant ProcID  : AlertLogIDType := NewID("ControlProc", TCID);
    constant TIMEOUT : time := 100 ms;
  begin
    SetTestName("fifo_cc_got_tempput_Simple_Config" & integer'image(tConfigIndex'pos(CONFIG_INDEX)));

    SetLogEnable(PASSED, FALSE);
    SetLogEnable(INFO,   TRUE);
    SetLogEnable(DEBUG,  FALSE);
    wait for 0 ns; wait for 0 ns;

    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    -- Initialize Operation Coverage
    -- Covers all input spec operations
    OpCov.AddBins("Idle",           GenBin(0));   -- ' ' - wait
    OpCov.AddBins("Put",            GenBin(1));   -- 'p' - put only
    OpCov.AddBins("Commit",         GenBin(2));   -- 'c' - commit only
    OpCov.AddBins("Put_Commit",     GenBin(3));   -- 'C' - put with commit
    OpCov.AddBins("Rollback",       GenBin(4));   -- 'r' - rollback only
    OpCov.AddBins("Put_Rollback",   GenBin(5));   -- 'R' - put with rollback
    OpCov.SetName("OperationCoverage");

    -- Initialize State Coverage
    StateCov.AddCross("Full_Valid",
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
    OpCov.WriteBin;
    StateCov.WriteBin;

    EndOfTestReports(ReportAll => TRUE);
    std.env.stop;
  end process;

  ----------------------------------------------------------------------------
  -- Writer Process - follows ISPEC script for write operations
  ----------------------------------------------------------------------------
  WriterProc : process
    constant ProcID : AlertLogIDType := NewID("WriterProc", TCID);
    variable PendingData : std_logic_vector(D_BITS*MIN_DEPTH-1 downto 0) := (others => '0');
    variable PendingCount : integer := 0;
  begin
    put      <= '0';
    din      <= (others => '-');
    commit   <= '0';
    rollback <= '0';
    putx     <= '0';
    wait until Reset = '0';
    WaitForClock(Clock);

    Log(ProcID, "Starting ISPEC-driven write sequence", INFO);

    for i in ISPEC'range loop
      put      <= '0';
      commit   <= '0';
      rollback <= '0';
      putx     <= '0';
      din      <= (others => '-');

      case ISPEC(i) is
        when ' ' =>
          -- Idle cycle
          OpCov.ICover(0);
          StateCov.ICover((to_integer(unsigned'('0' & full)), to_integer(unsigned'('0' & valid))));
          wait until rising_edge(Clock);

        when 'p' =>
          -- Put only (temporary write, not committed)
          din  <= di_scramble;
          put  <= '1';
          putx <= '1';
          -- Store in pending buffer
          PendingData(D_BITS*(PendingCount+1)-1 downto D_BITS*PendingCount) := di_scramble;
          PendingCount := PendingCount + 1;
          OpCov.ICover(1);
          StateCov.ICover((to_integer(unsigned'('0' & full)), to_integer(unsigned'('0' & valid))));
          wait until rising_edge(Clock) and full = '0';

        when 'c' =>
          -- Commit only
          commit <= '1';
          -- Move all pending data to scoreboard
          for j in 0 to PendingCount-1 loop
            FifoSB.Push(PendingData(D_BITS*(j+1)-1 downto D_BITS*j));
          end loop;
          PendingCount := 0;
          OpCov.ICover(2);
          StateCov.ICover((to_integer(unsigned'('0' & full)), to_integer(unsigned'('0' & valid))));
          wait until rising_edge(Clock);

        when 'C' =>
          -- Put with commit
          din    <= di_scramble;
          put    <= '1';
          putx   <= '1';
          commit <= '1';
          -- Store in pending buffer then commit all
          PendingData(D_BITS*(PendingCount+1)-1 downto D_BITS*PendingCount) := di_scramble;
          PendingCount := PendingCount + 1;
          for j in 0 to PendingCount-1 loop
            FifoSB.Push(PendingData(D_BITS*(j+1)-1 downto D_BITS*j));
          end loop;
          PendingCount := 0;
          OpCov.ICover(3);
          StateCov.ICover((to_integer(unsigned'('0' & full)), to_integer(unsigned'('0' & valid))));
          wait until rising_edge(Clock) and full = '0';

        when 'r' =>
          -- Rollback only (discard pending)
          rollback <= '1';
          PendingCount := 0;  -- Discard all pending
          OpCov.ICover(4);
          StateCov.ICover((to_integer(unsigned'('0' & full)), to_integer(unsigned'('0' & valid))));
          wait until rising_edge(Clock);

        when 'R' =>
          -- Put with rollback
          din      <= di_scramble;
          put      <= '1';
          putx     <= '1';
          rollback <= '1';
          PendingCount := 0;  -- Discard all pending including this one
          OpCov.ICover(5);
          StateCov.ICover((to_integer(unsigned'('0' & full)), to_integer(unsigned'('0' & valid))));
          wait until rising_edge(Clock) and full = '0';

        when others =>
          Alert(ProcID, "Illegal ISPEC character: " & ISPEC(i), FAILURE);
      end case;
    end loop;

    put      <= '0';
    commit   <= '0';
    rollback <= '0';
    putx     <= '0';
    din      <= (others => '-');

    Log(ProcID, "Writer completed ISPEC sequence", INFO);
    WaitForBarrier(TestDone);
    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Reader Process - follows OSPEC script for read operations
  ----------------------------------------------------------------------------
  ReaderProc : process
    constant ProcID  : AlertLogIDType := NewID("ReaderProc", TCID);
    variable Expected : tDataWord;
  begin
    got  <= '0';
    gotx <= '0';
    wait until Reset = '0';

    Log(ProcID, "Starting OSPEC-driven read sequence", INFO);

    for i in OSPEC'range loop
      case OSPEC(i) is
        when ' ' =>
          -- Idle cycle
          got  <= '0';
          gotx <= '0';
          wait until rising_edge(Clock);

        when 'g' =>
          -- Got - expect data to match scrambler output
          got <= '1';
          wait until rising_edge(Clock) and valid = '1';
          
          -- Get expected value from scoreboard
          if not FifoSB.Empty then
            Expected := FifoSB.Pop;
            AffirmIf(ProcID,
              dout = Expected,
              "Data match at OSPEC position " & integer'image(i) &
              ": Got 0x" & to_hstring(dout) &
              ", Expected 0x" & to_hstring(Expected) &
              " [" & ConfigToString(CONFIG_INDEX) & "]"
            );
          end if;
          
          gotx <= '1';
          got  <= '0';
          wait until rising_edge(Clock);
          gotx <= '0';

        when 'G' =>
          -- Got - expect data to NOT match (after rollback)
          got <= '1';
          wait until rising_edge(Clock) and valid = '1';
          
          -- After rollback, data should NOT match do_scramble
          AffirmIf(ProcID,
            dout /= do_scramble,
            "Data mismatch expected at OSPEC position " & integer'image(i) &
            " (after rollback): Got 0x" & to_hstring(dout) &
            ", Scrambler 0x" & to_hstring(do_scramble) &
            " [" & ConfigToString(CONFIG_INDEX) & "]"
          );
          
          got <= '0';
          wait until rising_edge(Clock);

        when others =>
          Alert(ProcID, "Illegal OSPEC character: " & OSPEC(i), FAILURE);
      end case;
    end loop;

    got  <= '0';
    gotx <= '0';

    Log(ProcID, "Reader completed OSPEC sequence", INFO);
    WaitForBarrier(TestDone);
    wait;
  end process;

end architecture;

-- Configuration for Simple test
configuration fifo_cc_got_tempput_Simple of fifo_cc_got_tempput_TestHarness is
  for TestHarness
    for TestCtrl : fifo_cc_got_tempput_TestController
      use entity work.fifo_cc_got_tempput_TestController(Simple);
    end for;
  end for;
end configuration;
