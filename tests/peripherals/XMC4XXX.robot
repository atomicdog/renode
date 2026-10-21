*** Variables ***
${XMC4500_REPL}                 @platforms/cpus/xmc4500.repl
${XMC4800_REPL}                 @platforms/cpus/xmc4800.repl

${SCU_IDCHIP}                   0x50004004
${USIC0_CH0_RBUF}               0x40030054
${USIC0_CH0_RBUFD}              0x40030058

*** Keywords ***
Create Machine
    [Arguments]                   ${repl}
    Execute Command               mach create
    Execute Command               machine LoadPlatformDescription ${repl}

Read Bus
    [Arguments]                   ${address}
    ${val}=                       Execute Command  sysbus ReadDoubleWord ${address}
    RETURN                        ${val.strip()}

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
