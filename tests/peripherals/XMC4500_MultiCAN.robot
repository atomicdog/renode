*** Variables ***
# Inline platform description — just the CAN peripheral, no CPU needed
${CAN_REPL}                     can: CAN.XMC4500_MultiCAN @ sysbus 0x48014000

# Register offsets (relative to CAN base)
${CLC}                          0x000
${ID}                           0x008
${PANCTR}                       0x1C4
${MSIMASK}                      0x1C0

# Node 0 registers
${N0CR}                         0x200
${N0SR}                         0x204
${N0IPR}                        0x208
${N0BTR}                        0x210

# Node 1 registers
${N1CR}                         0x300

# MO0 registers (offset 0x1000)
${MO0FCR}                       0x1000
${MO0IPR}                       0x1008
${MO0AMR}                       0x100C
${MO0DATAL}                     0x1010
${MO0DATAH}                     0x1014
${MO0AR}                        0x1018
${MO0STAT}                      0x101C

# MO1 registers (offset 0x1020)
${MO1FCR}                       0x1020
${MO1IPR}                       0x1028
${MO1AMR}                       0x102C
${MO1DATAL}                     0x1030
${MO1DATAH}                     0x1034
${MO1AR}                        0x1038
${MO1STAT}                      0x103C

# MO2 registers (offset 0x1040)
${MO2FCR}                       0x1040
${MO2IPR}                       0x1048
${MO2AMR}                       0x104C
${MO2DATAL}                     0x1050
${MO2DATAH}                     0x1054
${MO2AR}                        0x1058
${MO2STAT}                      0x105C

# MO3 registers (offset 0x1060)
${MO3FCR}                       0x1060
${MO3IPR}                       0x1068
${MO3AMR}                       0x106C
${MO3DATAL}                     0x1070
${MO3DATAH}                     0x1074
${MO3AR}                        0x1078
${MO3STAT}                      0x107C

# MSID and MSPND registers
${MSID0}                        0x180
${MSPND0}                       0x140

*** Keywords ***
Create Machine
    Execute Command               mach create
    Execute Command               machine LoadPlatformDescriptionFromString "${CAN_REPL}"

Write CAN Register
    [Arguments]                   ${offset}  ${value}
    Execute Command               can WriteDoubleWord ${offset} ${value}

Assert Register Equals
    [Arguments]                   ${offset}  ${expected}
    ${val}=                       Execute Command  can ReadDoubleWord ${offset}
    Should Be Equal               ${val}  ${expected}  strip_spaces=True

Assert Bits Set
    [Documentation]               Verify that all bits in mask are set at the given register offset
    [Arguments]                   ${offset}  ${mask}
    ${val}=                       Execute Command  can ReadDoubleWord ${offset}
    ${intval}=                    Evaluate  int('''${val}'''.strip(), 0)
    ${masked}=                    Evaluate  ${intval} & ${mask}
    Should Be Equal As Integers   ${masked}  ${mask}
    ...                           msg=Expected bits ${mask} set at offset ${offset}, got value ${intval}

Assert Bits Clear
    [Documentation]               Verify that all bits in mask are clear at the given register offset
    [Arguments]                   ${offset}  ${mask}
    ${val}=                       Execute Command  can ReadDoubleWord ${offset}
    ${intval}=                    Evaluate  int('''${val}'''.strip(), 0)
    ${masked}=                    Evaluate  ${intval} & ${mask}
    Should Be Equal As Integers   ${masked}  0
    ...                           msg=Expected bits ${mask} clear at offset ${offset}, got value ${intval}

Enable Module
    # Clear CLC.DISR to enable the module
    Write CAN Register            ${CLC}  0x00000000

Allocate MO To List
    [Documentation]               PANCTR static allocate: move MO to list (PANAR1=MO at [23:16], PANAR2=list at [31:24])
    [Arguments]                   ${mo_index}  ${list_index}
    ${cmd}=                       Evaluate  (${list_index} << 24) | (${mo_index} << 16) | 0x02
    Write CAN Register            ${PANCTR}  ${cmd}

Setup TX MO0
    [Documentation]               Configure MO0 for transmit with standard 11-bit ID
    [Arguments]                   ${can_id}  ${data_low}  ${data_high}=0x00000000  ${dlc}=8
    ${ar}=                        Evaluate  (${can_id} & 0x7FF) << 18
    Write CAN Register            ${MO0AR}  ${ar}
    ${fcr}=                       Evaluate  (${dlc} & 0xF) << 24
    Write CAN Register            ${MO0FCR}  ${fcr}
    Write CAN Register            ${MO0DATAL}  ${data_low}
    Write CAN Register            ${MO0DATAH}  ${data_high}
    # MOCTR: set MSGVAL(5) + TXEN0(9) + DIR(11) = 0x0A20 in upper half
    Write CAN Register            ${MO0STAT}  0x0A200000

Setup RX MO1
    [Documentation]               Configure MO1 for receive with exact standard ID match
    [Arguments]                   ${can_id}
    ${ar}=                        Evaluate  (${can_id} & 0x7FF) << 18
    Write CAN Register            ${MO1AR}  ${ar}
    # MOAMR: exact 11-bit match with MIDE=1 → 0x3FFC0000
    Write CAN Register            ${MO1AMR}  0x3FFC0000
    # MOCTR: set MSGVAL(5) + RXEN(7) = 0x00A0 in upper half
    Write CAN Register            ${MO1STAT}  0x00A00000

Trigger TX MO0
    [Documentation]               Set TXRQ on MO0
    Write CAN Register            ${MO0STAT}  0x01000000

Setup TX MO
    [Documentation]               Configure any MO for transmit with standard 11-bit ID
    [Arguments]                   ${stat_offset}  ${ar_offset}  ${fcr_offset}  ${datal_offset}  ${datah_offset}  ${can_id}  ${data_low}  ${data_high}=0x00000000  ${dlc}=8
    ${ar}=                        Evaluate  (${can_id} & 0x7FF) << 18
    Write CAN Register            ${ar_offset}  ${ar}
    ${fcr}=                       Evaluate  (${dlc} & 0xF) << 24
    Write CAN Register            ${fcr_offset}  ${fcr}
    Write CAN Register            ${datal_offset}  ${data_low}
    Write CAN Register            ${datah_offset}  ${data_high}
    Write CAN Register            ${stat_offset}  0x0A200000

Setup RX MO
    [Documentation]               Configure any MO for receive with exact standard ID match
    [Arguments]                   ${stat_offset}  ${ar_offset}  ${amr_offset}  ${can_id}
    ${ar}=                        Evaluate  (${can_id} & 0x7FF) << 18
    Write CAN Register            ${ar_offset}  ${ar}
    Write CAN Register            ${amr_offset}  0x3FFC0000
    Write CAN Register            ${stat_offset}  0x00A00000

Trigger TX
    [Documentation]               Set TXRQ on any MO by MOCTR offset
    [Arguments]                   ${stat_offset}
    Write CAN Register            ${stat_offset}  0x01000000

Wait For Bus Idle
    [Documentation]               Let virtual time pass so a TX deferred behind the previous frame goes out
    ...                           (8-byte standard frame at the default 2 us bit time: 222 us)
    Execute Command               emulation RunFor "0.001"

Read Register Value
    [Documentation]               Read a register and return its integer value
    [Arguments]                   ${offset}
    ${val}=                       Execute Command  can ReadDoubleWord ${offset}
    ${intval}=                    Evaluate  int('''${val}'''.strip(), 0)
    RETURN                        ${intval}

*** Test Cases ***
Should Have Correct Reset State
    [Documentation]               Verify reset values of key registers
    Create Machine

    # CLC: DISR=1, DISS=1 → 0x3
    Assert Register Equals        ${CLC}  0x00000003

    # Module ID
    Assert Register Equals        ${ID}  0x00B0C000

    # Node 0 NCR: INIT=1 → 0x01
    Assert Bits Set               ${N0CR}  ${1}

    # Node 1 NCR: INIT=1
    Assert Bits Set               ${N1CR}  ${1}

Should Enable Module By Clearing CLC DISR
    [Documentation]               Clearing DISR should also clear DISS
    Create Machine

    Write CAN Register            ${CLC}  0x00000000
    Assert Register Equals        ${CLC}  0x00000000

Should Gate NBTR Writes On CCE
    [Documentation]               NBTR writes should be ignored when CCE=0, accepted when CCE=1
    Create Machine
    Enable Module

    # NCR = 0x01 (INIT=1, CCE=0 by default) — try to write NBTR
    Write CAN Register            ${N0BTR}  0x00001234
    Assert Register Equals        ${N0BTR}  0x00000000

    # Set CCE: NCR = 0x41 (INIT=1, CCE=1)
    Write CAN Register            ${N0CR}  0x00000041

    # Now NBTR write should be accepted
    Write CAN Register            ${N0BTR}  0x00001234
    Assert Register Equals        ${N0BTR}  0x00001234

Should Suppress TX When Node INIT Is Set
    [Documentation]               TX should be suppressed when NCR.INIT=1, succeed when INIT=0
    Create Machine
    Enable Module

    # Keep INIT=1 on node 0 (default), set CCE for config
    Write CAN Register            ${N0CR}  0x00000041

    # Allocate MO0 to list 1 (node 0)
    Allocate MO To List           0  1

    # Configure MO0 for TX: ID=0x123, DLC=8, data=0xDEADBEEF
    Setup TX MO0                  0x123  0xDEADBEEF

    # Try TX with INIT=1 — should be suppressed
    Trigger TX MO0

    # TXRQ (bit 8) should still be set, TXPND (bit 1) should NOT be set
    Assert Bits Set               ${MO0STAT}  ${0x100}
    Assert Bits Clear             ${MO0STAT}  ${0x002}

    # Clear INIT: NCR = 0x40 (CCE=1, INIT=0)
    Write CAN Register            ${N0CR}  0x00000040

    # Clear TXRQ then re-trigger
    Write CAN Register            ${MO0STAT}  0x00000100
    Trigger TX MO0

    # TXRQ (bit 8) should be cleared, TXPND (bit 1) should be set
    Assert Bits Clear             ${MO0STAT}  ${0x100}
    Assert Bits Set               ${MO0STAT}  ${0x002}

Should Set NSR TXOK And Fire Transfer Interrupt On TX
    [Documentation]               After TX, NSR.TXOK should be set when TRIE is enabled
    Create Machine
    Enable Module

    # Node 0: CCE=1, TRIE=1, INIT=1
    Write CAN Register            ${N0CR}  0x00000043
    # Set TRINP=3 in NIPR (bits [2:0])
    Write CAN Register            ${N0IPR}  0x00000003

    # Allocate and configure MO0 for TX
    Allocate MO To List           0  1
    Setup TX MO0                  0x123  0xCAFEBABE

    # Clear INIT, keep TRIE
    Write CAN Register            ${N0CR}  0x00000002

    # Transmit
    Trigger TX MO0

    # NSR.TXOK (bit 3) should be set
    Assert Bits Set               ${N0SR}  ${0x08}

Should Receive Frame Via Loopback Mode
    [Documentation]               With NCR.LM set, TX frame should loop back to RX MO on same node
    Create Machine
    Enable Module

    # Node 0: CCE=1, INIT=1 for configuration
    Write CAN Register            ${N0CR}  0x00000041

    # Allocate MO0 (TX) and MO1 (RX) to list 1 (node 0)
    Allocate MO To List           0  1
    Allocate MO To List           1  1

    # Configure MO0 as TX: ID=0x123, data=0xCAFEBABE / 0x12345678
    Setup TX MO0                  0x123  0xCAFEBABE  0x12345678

    # Configure MO1 as RX: accept ID=0x123
    Setup RX MO1                  0x123

    # Enable loopback: NCR = LM(12) | INIT=0 → 0x1000
    Write CAN Register            ${N0CR}  0x00001000

    # Transmit on MO0
    Trigger TX MO0

    # MO0: TXPND (bit 1) should be set
    Assert Bits Set               ${MO0STAT}  ${0x002}

    # MO1: RXPND (bit 0) and NEWDAT (bit 3) should be set
    Assert Bits Set               ${MO1STAT}  ${0x001}
    Assert Bits Set               ${MO1STAT}  ${0x008}

    # MO1 data should match what was transmitted
    Assert Register Equals        ${MO1DATAL}  0xCAFEBABE
    Assert Register Equals        ${MO1DATAH}  0x12345678

Should Isolate Nodes In Loopback Mode
    [Documentation]               Loopback on Node 0 should not deliver frames to Node 1 RX MOs
    Create Machine
    Enable Module

    # Node 0: CCE=1, INIT=1
    Write CAN Register            ${N0CR}  0x00000041
    # Node 1: INIT=0
    Write CAN Register            ${N1CR}  0x00000000

    # Allocate MO0 to list 1 (node 0), MO1 to list 2 (node 1)
    Allocate MO To List           0  1
    Allocate MO To List           1  2

    # Configure MO0 as TX on node 0: ID=0x123, data=0xAAAAAAAA
    Setup TX MO0                  0x123  0xAAAAAAAA

    # Configure MO1 as RX on node 1: accept ID=0x123
    Setup RX MO1                  0x123

    # Enable loopback on node 0 only, clear INIT
    Write CAN Register            ${N0CR}  0x00001000

    # Transmit on MO0 (node 0)
    Trigger TX MO0

    # MO0 on node 0: TX should succeed
    Assert Bits Set               ${MO0STAT}  ${0x002}

    # MO1 on node 1: should NOT receive (loopback feeds same node only)
    Assert Bits Clear             ${MO1STAT}  ${0x001}
    Assert Bits Clear             ${MO1STAT}  ${0x008}

    # MO1 data should be untouched (still 0)
    Assert Register Equals        ${MO1DATAL}  0x00000000

Should Set MSGLST On Double Receive Without Clearing NEWDAT
    [Documentation]               If NEWDAT is already set when a second frame arrives, MSGLST should be set
    Create Machine
    Enable Module

    # Node 0: CCE=1, INIT=1
    Write CAN Register            ${N0CR}  0x00000041

    # Allocate MO0 (TX) and MO1 (RX) to list 1 (node 0)
    Allocate MO To List           0  1
    Allocate MO To List           1  1

    # Configure MO0 as TX: ID=0x123
    Setup TX MO0                  0x123  0x11111111

    # Configure MO1 as RX: accept ID=0x123
    Setup RX MO1                  0x123

    # Enable loopback, clear INIT
    Write CAN Register            ${N0CR}  0x00001000

    # First transmit — should set NEWDAT on MO1
    Trigger TX MO0
    Assert Bits Set               ${MO1STAT}  ${0x008}
    Assert Bits Clear             ${MO1STAT}  ${0x010}
    Assert Register Equals        ${MO1DATAL}  0x11111111

    # Change TX data for second frame
    Write CAN Register            ${MO0DATAL}  0x22222222

    # Second transmit WITHOUT clearing NEWDAT on MO1
    Trigger TX MO0

    # The first frame still occupies the bus, so the second is deferred
    Assert Bits Clear             ${MO1STAT}  ${0x010}
    Wait For Bus Idle

    # MO1: MSGLST (bit 4) should now be set
    Assert Bits Set               ${MO1STAT}  ${0x010}

    # MO1 data should be the second frame's data
    Assert Register Equals        ${MO1DATAL}  0x22222222

Should Set MSPND Bit On RX
    [Documentation]               RX should set the MSPND bit specified by MOIPR fields
    Create Machine
    Enable Module

    # Node 0: CCE=1, INIT=1
    Write CAN Register            ${N0CR}  0x00000041

    # Set MSIMASK to all-ones so MSID works
    Write CAN Register            ${MSIMASK}  0xFFFFFFFF

    # Allocate MO0 (TX) and MO1 (RX) to list 1 (node 0)
    Allocate MO To List           0  1
    Allocate MO To List           1  1

    # Configure MO0 as TX: ID=0x123
    Setup TX MO0                  0x123  0xBEEFBEEF

    # Configure MO1 as RX: accept ID=0x123
    Setup RX MO1                  0x123

    # Set MO1 MOIPR: RXINP=2 (bits[2:0]), MPN=5 (bits[15:8])
    # → should set MSPND[2] bit 5
    Write CAN Register            ${MO1IPR}  0x00000502

    # Enable loopback, clear INIT
    Write CAN Register            ${N0CR}  0x00001000

    # Transmit
    Trigger TX MO0

    # MSPND[2] (offset 0x148) bit 5 should be set
    Assert Bits Set               0x148  ${0x020}

Should Report PANCTR Not Busy After Reset And Commands
    [Documentation]               PANCTR should show command complete (BUSY=0) after reset and commands
    Create Machine

    # After reset: PANCMD=0x01 (init list completed), BUSY=0, RBUSY=0
    Assert Bits Clear             ${PANCTR}  ${0x300}
    # PANCMD should be 0x01
    ${val}=                       Read Register Value  ${PANCTR}
    ${pancmd}=                    Evaluate  ${val} & 0xFF
    Should Be Equal As Integers   ${pancmd}  1

    # Issue static allocate command
    Allocate MO To List           0  1

    # BUSY and RBUSY should still be 0 (instant execution)
    Assert Bits Clear             ${PANCTR}  ${0x300}

Should Clear NSR TXOK And RXOK Via Write 1 To Clear
    [Documentation]               Firmware clears NSR.TXOK/RXOK by writing 1 to those bits
    Create Machine
    Enable Module

    # Node 0: CCE=1, INIT=1
    Write CAN Register            ${N0CR}  0x00000041

    # Allocate MO0 (TX) and MO1 (RX) to list 1
    Allocate MO To List           0  1
    Allocate MO To List           1  1

    Setup TX MO0                  0x123  0xAAAAAAAA
    Setup RX MO1                  0x123

    # Enable loopback, clear INIT
    Write CAN Register            ${N0CR}  0x00001000

    # TX → sets TXOK and RXOK (loopback triggers RX too)
    Trigger TX MO0
    Assert Bits Set               ${N0SR}  ${0x08}
    Assert Bits Set               ${N0SR}  ${0x10}

    # Clear TXOK by writing 1 to bit 3
    Write CAN Register            ${N0SR}  0x00000008
    Assert Bits Clear             ${N0SR}  ${0x08}
    # RXOK should still be set
    Assert Bits Set               ${N0SR}  ${0x10}

    # Clear RXOK by writing 1 to bit 4
    Write CAN Register            ${N0SR}  0x00000010
    Assert Bits Clear             ${N0SR}  ${0x10}

Should Support Full MSID RX Processing Loop
    [Documentation]               Exercise the firmware's RX interrupt handler: MSID read → process MO → clear → next
    Create Machine
    Enable Module

    # Node 0: CCE=1, INIT=1
    Write CAN Register            ${N0CR}  0x00000041

    # Set MSIMASK to all-ones so MSID returns pending MO indices
    Write CAN Register            ${MSIMASK}  0xFFFFFFFF

    # Allocate MO0 (TX ID=0x100), MO1 (RX ID=0x100), MO2 (TX ID=0x200), MO3 (RX ID=0x200)
    Allocate MO To List           0  1
    Allocate MO To List           1  1
    Allocate MO To List           2  1
    Allocate MO To List           3  1

    # Configure MO0 as TX: ID=0x100, data=0x11111111
    # Set MOIPR TXINP=7 (bits[6:4]) so TX MSPND goes to MSPND[7], not MSPND[0]
    Setup TX MO                   ${MO0STAT}  ${MO0AR}  ${MO0FCR}  ${MO0DATAL}  ${MO0DATAH}  0x100  0x11111111
    Write CAN Register            ${MO0IPR}  0x00000070

    # Configure MO1 as RX: accept ID=0x100, RXINP=0, MPN=1
    Setup RX MO                   ${MO1STAT}  ${MO1AR}  ${MO1AMR}  0x100
    Write CAN Register            ${MO1IPR}  0x00000100

    # Configure MO2 as TX: ID=0x200, data=0x22222222
    # Set MOIPR TXINP=7 so TX MSPND goes to MSPND[7]
    Setup TX MO                   ${MO2STAT}  ${MO2AR}  ${MO2FCR}  ${MO2DATAL}  ${MO2DATAH}  0x200  0x22222222
    Write CAN Register            ${MO2IPR}  0x00000070

    # Configure MO3 as RX: accept ID=0x200, RXINP=0, MPN=3
    Setup RX MO                   ${MO3STAT}  ${MO3AR}  ${MO3AMR}  0x200
    Write CAN Register            ${MO3IPR}  0x00000300

    # Enable loopback, clear INIT
    Write CAN Register            ${N0CR}  0x00001000

    # Transmit both frames
    Trigger TX MO0
    Trigger TX                    ${MO2STAT}
    Wait For Bus Idle

    # Both RX MOs should have NEWDAT set
    Assert Bits Set               ${MO1STAT}  ${0x008}
    Assert Bits Set               ${MO3STAT}  ${0x008}

    # MSPND[0] should have bits 1 and 3 set
    Assert Bits Set               ${MSPND0}  ${0x00A}

    # === Firmware RX interrupt handler loop ===

    # Step 1: Read MSID[0] → should return 1 (lowest set bit in MSPND[0] & MSIMASK)
    ${msid}=                      Read Register Value  ${MSID0}
    Should Be Equal As Integers   ${msid}  1

    # Step 2: Read MO1 data (the MO at index returned by MSID)
    Assert Register Equals        ${MO1DATAL}  0x11111111

    # Step 3: Clear NEWDAT(3) and RXPND(0) on MO1 via MOCTR (bits in lower half)
    Write CAN Register            ${MO1STAT}  0x00000009

    # Step 4: Clear MSPND[0] bit 1 (write-1-to-clear)
    Write CAN Register            ${MSPND0}  0x00000002

    # Step 5: Read MSID[0] again → should return 3 (next pending)
    ${msid}=                      Read Register Value  ${MSID0}
    Should Be Equal As Integers   ${msid}  3

    # Step 6: Read MO3 data
    Assert Register Equals        ${MO3DATAL}  0x22222222

    # Step 7: Clear NEWDAT and RXPND on MO3
    Write CAN Register            ${MO3STAT}  0x00000009

    # Step 8: Clear MSPND[0] bit 3
    Write CAN Register            ${MSPND0}  0x00000008

    # Step 9: Read MSID[0] → should return 0x20 (no more pending)
    ${msid}=                      Read Register Value  ${MSID0}
    Should Be Equal As Integers   ${msid}  0x20

Should Pulse The RX Interrupt Line Once Per Frame Without Holding It
    [Documentation]               MultiCAN service requests are pulses: RXPND left set by a handler
    ...                           that returns early must not keep the line asserted
    Create Machine
    # Count rising edges on interrupt line 3
    Execute Command               python "pulses = [0]; line3 = self.Machine['sysbus.can'].Connections[3]; line3.AddStateChangedHook(lambda state: pulses.__setitem__(0, pulses[0] + (1 if state else 0)))"
    Enable Module

    # Node 0: CCE=1, INIT=1
    Write CAN Register            ${N0CR}  0x00000041
    Allocate MO To List           0  1
    Allocate MO To List           1  1
    Setup TX MO0                  0x123  0x11111111
    Setup RX MO1                  0x123
    # MO1: RXIE (MOFCR bit 16), RXINP = 3
    Write CAN Register            ${MO1FCR}  0x00010000
    Write CAN Register            ${MO1IPR}  0x00000003

    # Loopback, clear INIT
    Write CAN Register            ${N0CR}  0x00001000

    Trigger TX MO0
    Assert Bits Set               ${MO1STAT}  ${0x001}
    ${count}=                     Execute Command  python "print(pulses[0])"
    Should Be Equal As Integers   ${count}  1
    ${state}=                     Execute Command  python "print(line3.IsSet)"
    Should Be Equal               ${state}  False  strip_spaces=True

    # A second frame with RXPND still set pulses again
    Wait For Bus Idle
    Trigger TX MO0
    Wait For Bus Idle
    ${count}=                     Execute Command  python "print(pulses[0])"
    Should Be Equal As Integers   ${count}  2
