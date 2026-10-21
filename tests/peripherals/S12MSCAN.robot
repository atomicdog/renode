*** Settings ***
Library                         String

*** Variables ***
${A}                            0x1000
${B}                            0x2000

# Register offsets
${CANCTL0}                      0x00
${CANRFLG}                      0x04
${CANTFLG}                      0x06
${CANTBSEL}                     0x0A
${CANIDAC}                      0x0B
${CANIDAR0}                     0x10
${CANIDMR0}                     0x14
${CANIDAR4}                     0x18
${CANIDMR4}                     0x1C
${CANRXIDR0}                    0x20
${CANRXDSR0}                    0x24
${CANRXDLR}                     0x2C
${CANTXIDR0}                    0x30
${CANTXDSR0}                    0x34
${CANTXDLR}                     0x3C

*** Keywords ***
Create Two Nodes On A Hub
    Execute Command             mach create
    Execute Command             machine LoadPlatformDescriptionFromString "a: CAN.S12MSCAN @ sysbus ${A}"
    Execute Command             machine LoadPlatformDescriptionFromString "b: CAN.S12MSCAN @ sysbus ${B}"
    Execute Command             emulation CreateCANHub "hub"
    Execute Command             connector Connect sysbus.a hub
    Execute Command             connector Connect sysbus.b hub
    # Leave init mode
    Write Register              ${A}  ${CANCTL0}  0x00
    Write Register              ${B}  ${CANCTL0}  0x00

Write Register
    [Arguments]                 ${node}  ${offset}  ${value}
    Execute Command             sysbus WriteByte ${{${node} + ${offset}}} ${value}

Register Should Be
    [Arguments]                 ${node}  ${offset}  ${expected}
    ${value}=                   Execute Command  sysbus ReadByte ${{${node} + ${offset}}}
    Should Be Equal As Integers  ${value}  ${expected}

Set Filter Bank
    [Documentation]             Both 32-bit banks: IDR0 must match ${idr0} under ${mask0}; IDR1-3 ignored
    [Arguments]                 ${node}  ${idr0}  ${mask0}
    FOR  ${bank}  IN  ${CANIDAR0}  ${CANIDAR4}
        Write Register          ${node}  ${bank}  ${idr0}
        Write Register          ${node}  ${{${bank} + 4}}  ${mask0}
        Write Register          ${node}  ${{${bank} + 5}}  0xFF
        Write Register          ${node}  ${{${bank} + 6}}  0xFF
        Write Register          ${node}  ${{${bank} + 7}}  0xFF
    END

Write Filter Registers
    [Documentation]             IDAR0-3, IDMR0-3, IDAR4-7, IDMR4-7 (0x10-0x1F) in register order
    [Arguments]                 ${node}  ${hex}
    @{bytes}=                   Split String  ${hex}
    FOR  ${i}  ${byte}  IN ENUMERATE  @{bytes}
        Write Register          ${node}  ${{${CANIDAR0} + ${i}}}  0x${byte}
    END

Release RX Buffer
    [Arguments]                 ${node}
    Write Register              ${node}  ${CANRFLG}  0x01

Frame Should Hit Filter
    [Arguments]                 ${idr0}  ${idr1}  ${expected_idac}
    Send Standard Frame From A  ${idr0}  ${idr1}
    Register Should Be          ${B}  ${CANRFLG}  0x01
    Register Should Be          ${B}  ${CANRXIDR0}  ${idr0}
    Register Should Be          ${B}  ${CANIDAC}  ${expected_idac}
    Release RX Buffer           ${B}

Send Standard Frame From A
    [Arguments]                 ${idr0}  ${idr1}
    Write Register              ${A}  ${CANTBSEL}  0x01
    Write Register              ${A}  ${CANTXIDR0}  ${idr0}
    Write Register              ${A}  ${{${CANTXIDR0} + 1}}  ${idr1}
    Write Register              ${A}  ${CANTXDSR0}  0x11
    Write Register              ${A}  ${{${CANTXDSR0} + 1}}  0x22
    Write Register              ${A}  ${CANTXDLR}  0x02
    Write Register              ${A}  ${CANTFLG}  0x01
    Execute Command             emulation RunFor "0.001"

*** Test Cases ***
Should Deliver A Standard Frame To Another Node
    Create Two Nodes On A Hub
    Set Filter Bank             ${B}  0x00  0xFF

    # ID 0x480: IDR0 = ID[10:3] = 0x90, IDR1 = ID[2:0] << 5 = 0x00
    Send Standard Frame From A  0x90  0x00

    Register Should Be          ${A}  ${CANTFLG}  0x07
    Register Should Be          ${B}  ${CANRFLG}  0x01
    Register Should Be          ${B}  ${CANRXIDR0}  0x90
    Register Should Be          ${B}  ${{${CANRXIDR0} + 1}}  0x00
    Register Should Be          ${B}  ${CANRXDSR0}  0x11
    Register Should Be          ${B}  ${{${CANRXDSR0} + 1}}  0x22
    Register Should Be          ${B}  ${CANRXDLR}  0x02

Should Drop Frames Rejected By The Acceptance Filter
    Create Two Nodes On A Hub
    # Accept only IDR0 = 0x10 (IDs 0x080-0x087)
    Set Filter Bank             ${B}  0x10  0x00
    Register Should Be          ${B}  ${CANIDMR0}  0x00
    Register Should Be          ${B}  ${CANIDAR4}  0x10

    Send Standard Frame From A  0x90  0x00
    Register Should Be          ${B}  ${CANRFLG}  0x00

    Send Standard Frame From A  0x10  0x20
    Register Should Be          ${B}  ${CANRFLG}  0x01
    Register Should Be          ${B}  ${CANRXIDR0}  0x10
    Register Should Be          ${B}  ${{${CANRXIDR0} + 1}}  0x20

Should Ignore Frames In Init Mode
    Create Two Nodes On A Hub
    Set Filter Bank             ${B}  0x00  0xFF
    Write Register              ${B}  ${CANCTL0}  0x01

    Send Standard Frame From A  0x90  0x00
    Register Should Be          ${B}  ${CANRFLG}  0x00

Should Match Four 16-Bit Filters And Report IDHIT
    Create Two Nodes On A Hub
    Write Register              ${B}  ${CANIDAC}  0x10
    # Filter k compares IDAR(2k)-(2k+1) with IDR0-1; IDMR 0x07 ignores IDR1[2:0]
    #   0: ID 0x791    1: ID 0x080    2: ID 0x100    3: ID 0x180
    Write Filter Registers      ${B}  F2 20 10 00 00 07 00 07 20 00 30 00 00 07 00 07

    Frame Should Hit Filter     0xF2  0x20  0x10
    Frame Should Hit Filter     0x20  0x00  0x12
    Frame Should Hit Filter     0x30  0x00  0x13
    Frame Should Hit Filter     0x10  0x00  0x11

    # ID 0x200 matches none of them
    Send Standard Frame From A  0x40  0x00
    Register Should Be          ${B}  ${CANRFLG}  0x00

Should Match Eight 8-Bit Filters On IDR0 Only
    Create Two Nodes On A Hub
    Write Register              ${B}  ${CANIDAC}  0x20
    # Only IDAR5 (0x19) accepts IDR0 = 0x90; all masks clear
    Write Filter Registers      ${B}  FF FF FF FF 00 00 00 00 FF 90 FF FF 00 00 00 00

    Frame Should Hit Filter     0x90  0x00  0x25
    # IDR1 (ID[2:0]) is not compared in 8-bit mode: ID 0x487 hits too
    Frame Should Hit Filter     0x90  0xE0  0x25

    Send Standard Frame From A  0x91  0x00
    Register Should Be          ${B}  ${CANRFLG}  0x00

Should Accept Nothing With The Filters Closed
    Create Two Nodes On A Hub
    Write Register              ${B}  ${CANIDAC}  0x30
    Write Filter Registers      ${B}  00 00 00 00 FF FF FF FF 00 00 00 00 FF FF FF FF

    Send Standard Frame From A  0x90  0x00
    Register Should Be          ${B}  ${CANRFLG}  0x00

Should Keep IDHIT Read Only
    Create Two Nodes On A Hub
    Write Register              ${B}  ${CANIDAC}  0x17
    Register Should Be          ${B}  ${CANIDAC}  0x10
