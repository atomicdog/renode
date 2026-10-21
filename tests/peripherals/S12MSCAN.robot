*** Variables ***
${A}                            0x1000
${B}                            0x2000

# Register offsets
${CANCTL0}                      0x00
${CANRFLG}                      0x04
${CANTFLG}                      0x06
${CANTBSEL}                     0x0A
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
