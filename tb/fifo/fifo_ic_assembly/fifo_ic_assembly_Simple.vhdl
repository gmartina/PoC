-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:					Thomas B. Preusser
--                  Gustavo Martin
--
-- Architecture:		fifo_ic_assembly_Simple
--
-- Description:
-- -------------------------------------
-- Simple OSVVM test for fifo_ic_assembly
-- Tests out-of-order data reassembly capability
-- Uses OSVVM Scoreboard for data integrity verification
-- Uses OSVVM Functional Coverage for sequence pattern coverage
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

use     work.fifo_ic_assembly_TestController_pkg.all;

architecture Simple of fifo_ic_assembly_TestController is
  -- Test synchronization
  signal TestDone   : integer_barrier := 1;
  signal WriterDone : std_logic := '0';

  -- Alert/Log IDs
  constant TCID : AlertLogIDType := NewID("FifoIcAssemblyTest");

  -- Scoreboard for FIFO data verification
  shared variable FifoSB : osvvm.ScoreboardPkg_slv.ScoreboardPType;

  -- Functional Coverage
  shared variable SeqCov   : CovPType;  -- Sequence index coverage
  shared variable AddrCov  : CovPType;  -- Address coverage
  shared variable OrderCov : CovPType;  -- Out-of-order vs in-order coverage

begin
  ----------------------------------------------------------------------------
  -- Control Process - manages test lifecycle
  ----------------------------------------------------------------------------
  ControlProc : process
    constant ProcID  : AlertLogIDType := NewID("ControlProc", TCID);
    constant TIMEOUT : time := 500 ms;
  begin
    SetTestName("fifo_ic_assembly_Simple");

    SetLogEnable(PASSED, FALSE);
    SetLogEnable(INFO,   TRUE);
    SetLogEnable(DEBUG,  FALSE);
    wait for 0 ns; wait for 0 ns;

    TranscriptOpen;
    SetTranscriptMirror(TRUE);

    -- Initialize Scoreboard
    FifoSB.SetAlertLogID("FifoScoreboard");

    -- Initialize Sequence Coverage
    for i in SEQ'range loop
      SeqCov.AddBins("Seq_" & integer'image(i), GenBin(i));
    end loop;
    SeqCov.SetName("SequenceCoverage");

    -- Initialize Address Coverage (cover address ranges)
    AddrCov.AddBins("Addr_0_63",    GenBin(0, 63));
    AddrCov.AddBins("Addr_64_127",  GenBin(64, 127));
    AddrCov.AddBins("Addr_128_191", GenBin(128, 191));
    AddrCov.AddBins("Addr_192_255", GenBin(192, 255));
    AddrCov.SetName("AddressCoverage");

    -- Initialize Order Coverage
    OrderCov.AddBins("In_Order",     GenBin(0));  -- Sequential address
    OrderCov.AddBins("Out_Of_Order", GenBin(1));  -- Non-sequential address
    OrderCov.SetName("OrderingCoverage");

    -- Wait for base to become 0 (initialization complete)
    wait until base = (base'range => '0');
    ClearAlerts;

    WaitForBarrier(TestDone, TIMEOUT);
    AlertIf(ProcID, now >= TIMEOUT, "Test finished due to timeout");
    AlertIf(ProcID, GetAffirmCount < 1, "Test is not Self-Checking");

    -- Report Coverage results
    Log(ProcID, "=== Coverage Reports ===", ALWAYS);
    SeqCov.WriteBin;
    AddrCov.WriteBin;
    OrderCov.WriteBin;

    EndOfTestReports(ReportAll => TRUE);
    std.env.stop;
  end process;

  ----------------------------------------------------------------------------
  -- Writer Process - writes data out-of-order according to SEQ pattern
  ----------------------------------------------------------------------------
  WriterProc : process
    constant ProcID   : AlertLogIDType := NewID("WriterProc", TCID);
    variable t        : integer;
    variable LastAddr : integer := -1;
  begin
    put  <= '0';
    addr <= (others => '0');
    din  <= (others => '0');
    WriterDone <= '0';

    -- Wait for base to become 0 (initialization complete)
    wait until base = (base'range => '0');
    WaitForClock(Clock);

    Log(ProcID, "Starting out-of-order write sequence", INFO);

    -- Repeat the sequence 3 times for thorough testing
    for k in 0 to 2 loop
      Log(ProcID, "Pass " & integer'image(k), INFO);
      
      for i in SEQ'range loop
        -- Cover sequence index
        SeqCov.ICover(i);
        
        for j in 0 to 15 loop
          t := 16*SEQ(i) + j;
          
          -- Wait until address is within allowable range
          -- Only addresses in [base, base+2**(A_BITS-G_BITS)) are acceptable
          while ((t - to_integer(unsigned(base))) mod 2**A_BITS) / (2**(A_BITS-G_BITS)) /= 0 loop
            wait on base;
          end loop;
          
          -- Write data
          put  <= '1';
          addr <= std_logic_vector(to_unsigned(t, addr'length));
          din  <= not std_logic_vector(to_unsigned(t, din'length));  -- Data is inverted address
          
          -- Push expected value to scoreboard (in sequential order)
          -- Note: We push in the order they SHOULD appear at output
          FifoSB.Push(not std_logic_vector(to_unsigned(k*256 + i*16 + j, din'length)));
          
          -- Cover address and ordering
          AddrCov.ICover(t mod 256);
          if t = LastAddr + 1 then
            OrderCov.ICover(0);  -- In order
          else
            OrderCov.ICover(1);  -- Out of order
          end if;
          LastAddr := t;
          
          wait until rising_edge(Clock);
          put <= '0';
        end loop;

        -- Variable delay between blocks
        for delay in 0 to i/2 loop
          wait until rising_edge(Clock);
        end loop;
      end loop;
    end loop;

    put <= '0';
    WriterDone <= '1';
    Log(ProcID, "Writer completed", INFO);
    
    WaitForBarrier(TestDone);
    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Reader Process - reads data and verifies sequential order
  ----------------------------------------------------------------------------
  ReaderProc : process
    constant ProcID    : AlertLogIDType := NewID("ReaderProc", TCID);
    variable i         : integer := 0;
    variable Expected  : tDataWord;
    variable ReadCount : integer := 0;
  begin
    got <= '1';

    -- Wait for base to become 0
    wait until base = (base'range => '0');

    Log(ProcID, "Starting sequential read verification", INFO);

    while (WriterDone = '0') or (valid = '1') or (not FifoSB.Empty) loop
      wait until rising_edge(Clock);
      
      if valid = '1' then
        -- Verify data comes out in sequential order
        -- Expected value is inverted sequential counter
        if not FifoSB.Empty then
          Expected := FifoSB.Pop;
          
          AffirmIf(ProcID,
            unsigned(not dout) = (i mod 2**dout'length),
            "Sequential order check at position " & integer'image(i) &
            ": Got 0x" & to_hstring(dout) &
            " (inverted: " & integer'image(to_integer(unsigned(not dout))) & ")" &
            ", Expected sequential value: " & integer'image(i mod 2**dout'length)
          );
          
          ReadCount := ReadCount + 1;
        end if;
        
        got <= '0';
        
        -- Variable delay between reads
        for delay in 0 to i/dout'length loop
          wait until rising_edge(Clock);
        end loop;
        
        got <= '1';
        i := i + 1;
      end if;
    end loop;

    Log(ProcID, "Reader completed - read " & integer'image(ReadCount) & " words", INFO);

    WaitForBarrier(TestDone);
    wait;
  end process;

end architecture;

-- Configuration for Simple test
configuration fifo_ic_assembly_Simple of fifo_ic_assembly_TestHarness is
  for TestHarness
    for TestCtrl : fifo_ic_assembly_TestController
      use entity work.fifo_ic_assembly_TestController(Simple);
    end for;
  end for;
end configuration;
