*** Variables ***
${XMC4500_REPL}                 @platforms/cpus/xmc4500.repl
${XMC4800_REPL}                 @platforms/cpus/xmc4800.repl

${SCU_IDCHIP}                   0x50004004
${USIC0_CH0_RBUF}               0x40030054
${USIC0_CH0_RBUFD}              0x40030058

${VADC_BRSSEL0}                 0x40004180
${VADC_BRSMR}                   0x40004204
${VADC_G0_CHCTR1}               0x40004604
${VADC_G0_CHCTR2}               0x40004608
${VADC_G0_RES5}                 0x40004714
${VADC_G0_RES6}                 0x40004718

*** Keywords ***
Create Machine
    [Arguments]                   ${repl}
    Execute Command               mach create
    Execute Command               machine LoadPlatformDescription ${repl}

Read Bus
    [Arguments]                   ${address}
    ${val}=                       Execute Command  sysbus ReadDoubleWord ${address}
    RETURN                        ${val.strip()}

Run Background Scan Of G0 Channels
    [Arguments]                   ${select}
    Execute Command               cpu IsHalted true
    Execute Command               sysbus WriteDoubleWord ${VADC_BRSSEL0} ${select}
    # ENGT = 01 (conversion requests enabled) and LDEV: a load event starts the scan
    Execute Command               sysbus WriteDoubleWord ${VADC_BRSMR} 0x201
    Execute Command               emulation RunFor "0.001"

*** Test Cases ***
Should Load XMC4500 Platform
    Create Machine                ${XMC4500_REPL}
    ${id}=                        Read Bus  ${SCU_IDCHIP}
    Should Be Equal As Integers   ${id}  0x00004B01

Should Load XMC4800 Platform
    Create Machine                ${XMC4800_REPL}

Should Receive Carriage Return Alone By Default
    Create Machine                ${XMC4500_REPL}
    Execute Command               usic0ch0 WriteChar 0x0D

    ${b}=                         Read Bus  ${USIC0_CH0_RBUF}
    Should Be Equal As Integers   ${b}  0x0D
    ${b}=                         Read Bus  ${USIC0_CH0_RBUFD}
    Should Be Equal As Integers   ${b}  0x00

Should Append Line Feed After Carriage Return When Enabled
    Create Machine                ${XMC4500_REPL}
    Execute Command               usic0ch0 AppendLineFeedAfterCarriageReturn true
    Execute Command               usic0ch0 WriteChar 0x41
    Execute Command               usic0ch0 WriteChar 0x0D

    ${b}=                         Read Bus  ${USIC0_CH0_RBUF}
    Should Be Equal As Integers   ${b}  0x41
    ${b}=                         Read Bus  ${USIC0_CH0_RBUF}
    Should Be Equal As Integers   ${b}  0x0D
    ${b}=                         Read Bus  ${USIC0_CH0_RBUF}
    Should Be Equal As Integers   ${b}  0x0A

Should Store A Driven Channel In The Result Register Its CHCTR Selects
    Create Machine                ${XMC4500_REPL}
    # G0CH1: RESREG = 5
    Execute Command               sysbus WriteDoubleWord ${VADC_G0_CHCTR1} 0x50000
    Execute Command               vadc SetChannelValue 0 1 3521
    Run Background Scan Of G0 Channels  0x2

    ${r}=                         Read Bus  ${VADC_G0_RES5}
    Should Be Equal As Integers   ${r}  0x80000DC1

Should Keep SetResultValue For Undriven Channels And Convert Millivolts Against VAREF
    Create Machine                ${XMC4500_REPL}
    # G0CH1 -> RESREG 5 (driven, 1650 mV of the default 3300 mV VAREF);
    # G0CH2 -> RESREG 6 (not driven)
    Execute Command               sysbus WriteDoubleWord ${VADC_G0_CHCTR1} 0x50000
    Execute Command               sysbus WriteDoubleWord ${VADC_G0_CHCTR2} 0x60000
    Execute Command               vadc SetResultValue 0 6 1234
    Execute Command               vadc SetChannelMillivolts 0 1 1650
    Run Background Scan Of G0 Channels  0x6

    ${r}=                         Read Bus  ${VADC_G0_RES5}
    Should Be Equal As Integers   ${r}  0x80000800
    ${r}=                         Read Bus  ${VADC_G0_RES6}
    Should Be Equal As Integers   ${r}  0x800004D2
