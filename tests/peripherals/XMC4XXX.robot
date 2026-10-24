*** Variables ***
${XMC4500_REPL}                 @platforms/cpus/xmc4500.repl
${XMC4800_REPL}                 @platforms/cpus/xmc4800.repl

${SCU_IDCHIP}                   0x50004004
${USIC0_CH0_RBUF}               0x40030054
${USIC0_CH0_RBUFD}              0x40030058

${VADC_GLOBCFG}                  0x40004080
${VADC_BRSSEL0}                 0x40004180
${VADC_BRSSEL1}                 0x40004184
${VADC_BRSMR}                   0x40004204
${VADC_G0_CHCTR1}               0x40004604
${VADC_G0_CHCTR2}               0x40004608
${VADC_G0_RES5}                 0x40004714
${VADC_G0_RES6}                 0x40004718
${VADC_G1_CHCTR1}               0x40004A04
${VADC_G1_RES5}                 0x40004B14

${CCU40_GSTAT}                  0x4000C004
${CCU40_GIDLS}                  0x4000C008
${CCU40_GIDLC}                  0x4000C00C
${CCU40_GCSS}                   0x4000C010
${CCU40_CC40_TCST}              0x4000C108
${CCU40_CC40_TCSET}             0x4000C10C
${CCU40_CC40_TCCLR}             0x4000C110
${CCU40_CC40_PSL}               0x4000C118
${CCU40_CC40_PR}                0x4000C130
${CCU40_CC40_PRS}               0x4000C134
${CCU40_CC40_CR}                0x4000C138
${CCU40_CC40_CRS}               0x4000C13C
${CCU40_CC40_TIMER}             0x4000C170
${CCU40_CC41_PR}                0x4000C230
${CCU40_CC41_PRS}               0x4000C234

${ADS79XX}                      sysbus.usic0ch0.adc
${LTC6812}                      sysbus.usic1ch1.ltc

*** Keywords ***
Create Machine
    [Arguments]                   ${repl}
    Execute Command               mach create
    Execute Command               machine LoadPlatformDescription ${repl}

Read Bus
    [Arguments]                   ${address}
    ${val}=                       Execute Command  sysbus ReadDoubleWord ${address}
    RETURN                        ${val.strip()}

Create Machine With TI ADS79xx
    Create Machine                ${XMC4500_REPL}
    Execute Command               machine LoadPlatformDescriptionFromString "adc: Analog.TI_ADS79xx @ usic0ch0"

Send ADS79xx Frame
    [Arguments]                   ${high}  ${low}
    # Returns the frame's first output byte, DO15-08
    ${b}=                         Execute Command  ${ADS79XX} Transmit ${high}
    Execute Command               ${ADS79XX} Transmit ${low}
    RETURN                        ${b.strip()}

ADS79xx GPIO Should Be
    [Arguments]                   ${pin}  ${expected}
    ${state}=                     Execute Command  python "print(self.Machine['${ADS79XX}'].Connections[${pin}].IsSet)"
    Should Be Equal               ${state.strip()}  ${expected}

Create Machine With LTC6812
    Create Machine                ${XMC4500_REPL}
    Execute Command               machine LoadPlatformDescriptionFromString "ltc: SPI.LTC6812 @ usic1ch1"
    Execute Command               cpu IsHalted true

Create Machine With A Timed SPI Master
    [Arguments]                   ${stalls}
    Execute Command               mach create
    ${platform}=                  Catenate  SEPARATOR=\n
    ...                           using "platforms/cpus/xmc4500.repl"
    ...                           usic1ch1:
    ...                           ${SPACE*4}peripheralClockFrequency: 120000000
    ...                           ${SPACE*4}SpiTimingStallsCpu: ${stalls}
    ...                           ltc: SPI.LTC6812 @ usic1ch1
    Execute Command               machine LoadPlatformDescriptionFromString '${platform}'
    # USIC1_CH1 FDR, BRG, SCTR, PCR, CCR: SSC mode, 1 MHz SCLK from fPB = 120 MHz (FDR 0.75, PDIV 44), 8-bit
    # one-word frames with MSLS and inter-word delays: 14 us per word, received
    # after 10 us (2 us leading delay + 8 bits)
    Execute Command               sysbus WriteDoubleWord 0x48020210 0x8300
    Execute Command               sysbus WriteDoubleWord 0x48020214 0x002C0500
    Execute Command               sysbus WriteDoubleWord 0x48020234 0x07070000
    Execute Command               sysbus WriteDoubleWord 0x4802023C 0x01000127
    Execute Command               sysbus WriteDoubleWord 0x48020240 0x1
    Execute Command               cpu PerformanceInMips 100

Load One SPI Word Program
    # ldr r0, [pc, #8]; movs r1, #0x55; str r1, [r0]; 1: adds r2, #1; b 1b;
    # nop; .word TBUF00 (a counting loop: tlib idles on a branch to itself)
    Execute Command               sysbus WriteDoubleWord 0x20000000 0x21554802
    Execute Command               sysbus WriteDoubleWord 0x20000004 0x32016001
    Execute Command               sysbus WriteDoubleWord 0x20000008 0xBF00E7FD
    Execute Command               sysbus WriteDoubleWord 0x2000000C 0x48020280

Count Pulses On USIC1_CH1 Service Request
    [Arguments]                   ${node}
    Execute Command               python "pulses = [0]; self.Machine['sysbus.usic1ch1'].IRQ${node}.AddStateChangedHook(lambda state: pulses.__setitem__(0, pulses[0] + (1 if state else 0)))"

Pulses Should Be
    [Arguments]                   ${expected}
    ${n}=                         Execute Command  python "print(pulses[0])"
    Should Be Equal As Integers   ${n.strip()}  ${expected}

Instructions Executed In 100 us
    Execute Command               cpu PC 0x20000000
    Execute Command               emulation RunFor "0.0001"
    ${n}=                         Execute Command  cpu ExecutedInstructions
    RETURN                        ${n.strip()}

Send LTC6812 Bytes
    [Arguments]                   @{bytes}
    FOR  ${b}  IN  @{bytes}
        Execute Command           ${LTC6812} Transmit ${b}
    END

LTC6812 SDO Should Read
    [Arguments]                   ${expected}
    ${b}=                         Execute Command  ${LTC6812} Transmit 0x00
    Should Be Equal As Integers   ${b.strip()}  ${expected}

Load CCU40 Slice 0 Period And Compare
    [Arguments]                   ${period}  ${compare}
    Execute Command               sysbus WriteDoubleWord ${CCU40_CC40_PRS} ${period}
    Execute Command               sysbus WriteDoubleWord ${CCU40_CC40_CRS} ${compare}
    # S0SE: shadow transfer for slice 0
    Execute Command               sysbus WriteDoubleWord ${CCU40_GCSS} 0x1

Create Machine With Timed VADC
    Execute Command               mach create
    Execute Command               machine LoadPlatformDescriptionFromString "using \\"platforms/cpus/xmc4500.repl\\"; vadc: { peripheralClockFrequency: 60000000 }"

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

Should Take The Conversions Of All Groups For One Background Scan
    Create Machine With Timed VADC
    # DIVA = 15: fADCI = 60 MHz / 16. With the reset input class (STC 0,
    # 12-bit) and post-calibration a conversion is 16 tADCI + 2 tADC, plus a
    # 4-slot arbitration round: 4.37 us per channel.
    Execute Command               sysbus WriteDoubleWord ${VADC_GLOBCFG} 0xF
    # G0CH1 and G1CH1 -> RESREG 5 of their groups
    Execute Command               sysbus WriteDoubleWord ${VADC_G0_CHCTR1} 0x50000
    Execute Command               sysbus WriteDoubleWord ${VADC_G1_CHCTR1} 0x50000
    Execute Command               vadc SetChannelValue 0 1 100
    Execute Command               vadc SetChannelValue 1 1 200
    Execute Command               cpu IsHalted true
    Execute Command               sysbus WriteDoubleWord ${VADC_BRSSEL0} 0x2
    Execute Command               sysbus WriteDoubleWord ${VADC_BRSSEL1} 0x2
    Execute Command               sysbus WriteDoubleWord ${VADC_BRSMR} 0x201

    # One channel's time has passed but not two (8.73 us): the scan is still
    # running and RES5 holds its reset value.
    Execute Command               emulation RunFor "0.000006"
    ${r}=                         Read Bus  ${VADC_G0_RES5}
    Should Be Equal As Integers   ${r}  0x80000000
    Execute Command               emulation RunFor "0.000004"
    ${r}=                         Read Bus  ${VADC_G0_RES5}
    Should Be Equal As Integers   ${r}  0x80000064
    ${r}=                         Read Bus  ${VADC_G1_RES5}
    Should Be Equal As Integers   ${r}  0x800000C8

Should Transfer CCU4 Shadow Registers Only For The Requested Slices
    Create Machine                ${XMC4500_REPL}
    Execute Command               sysbus WriteDoubleWord ${CCU40_CC41_PRS} 0x1234
    Load CCU40 Slice 0 Period And Compare  99  75

    ${r}=                         Read Bus  ${CCU40_CC40_PR}
    Should Be Equal As Integers   ${r}  99
    ${r}=                         Read Bus  ${CCU40_CC40_CR}
    Should Be Equal As Integers   ${r}  75
    ${r}=                         Read Bus  ${CCU40_CC41_PR}
    Should Be Equal As Integers   ${r}  0
    ${r}=                         Read Bus  ${CCU40_GCSS}
    Should Be Equal As Integers   ${r}  0

Should Set And Clear The CCU4 Run And Idle Bits
    Create Machine                ${XMC4500_REPL}
    ${r}=                         Read Bus  ${CCU40_GSTAT}
    Should Be Equal As Integers   ${r}  0xF
    Execute Command               sysbus WriteDoubleWord ${CCU40_GIDLC} 0x1
    ${r}=                         Read Bus  ${CCU40_GSTAT}
    Should Be Equal As Integers   ${r}  0xE

    Execute Command               sysbus WriteDoubleWord ${CCU40_CC40_TCSET} 0x1
    ${r}=                         Read Bus  ${CCU40_CC40_TCST}
    Should Be Equal As Integers   ${r}  0x1
    ${r}=                         Read Bus  ${CCU40_CC40_TCSET}
    Should Be Equal As Integers   ${r}  0

    # TRBC and TCC: stop the timer and clear its value
    Execute Command               sysbus WriteDoubleWord ${CCU40_CC40_TIMER} 0x55
    Execute Command               sysbus WriteDoubleWord ${CCU40_CC40_TCCLR} 0x3
    ${r}=                         Read Bus  ${CCU40_CC40_TCST}
    Should Be Equal As Integers   ${r}  0
    ${r}=                         Read Bus  ${CCU40_CC40_TIMER}
    Should Be Equal As Integers   ${r}  0

    Execute Command               sysbus WriteDoubleWord ${CCU40_GIDLS} 0x1
    ${r}=                         Read Bus  ${CCU40_GSTAT}
    Should Be Equal As Integers   ${r}  0xF

Should Report The CCU4 Output Duty From Period Compare And Passive Level
    Create Machine                ${XMC4500_REPL}
    Load CCU40 Slice 0 Period And Compare  99  75

    # Stopped: the passive level
    ${d}=                         Execute Command  ccu40 GetOutputDuty 0
    Should Be Equal As Numbers    ${d.strip()}  0
    # Running, edge-aligned: high from compare match (75) to period match (99)
    Execute Command               sysbus WriteDoubleWord ${CCU40_CC40_TCSET} 0x1
    ${d}=                         Execute Command  ccu40 GetOutputDuty 0
    Should Be Equal As Numbers    ${d.strip()}  0.25
    Execute Command               sysbus WriteDoubleWord ${CCU40_CC40_PSL} 0x1
    ${d}=                         Execute Command  ccu40 GetOutputDuty 0
    Should Be Equal As Numbers    ${d.strip()}  0.75
    Execute Command               sysbus WriteDoubleWord ${CCU40_CC40_TCCLR} 0x1
    ${d}=                         Execute Command  ccu40 GetOutputDuty 0
    Should Be Equal As Numbers    ${d.strip()}  1

Should Drive TI ADS79xx GPIO Outputs From Mode Control Frames
    Create Machine With TI ADS79xx
    # GPIO program register: GPIO0 and GPIO1 are outputs
    Send ADS79xx Frame            0x40  0x03
    # Manual mode, DI11 set, GPIO data 0101: GPIO2 is an input and stays low
    Send ADS79xx Frame            0x18  0x05
    ADS79xx GPIO Should Be        0  True
    ADS79xx GPIO Should Be        1  False
    ADS79xx GPIO Should Be        2  False

    # Without DI11 the frame does not change the outputs
    Send ADS79xx Frame            0x10  0x02
    ADS79xx GPIO Should Be        0  True
    Send ADS79xx Frame            0x18  0x02
    ADS79xx GPIO Should Be        0  False
    ADS79xx GPIO Should Be        1  True

Should Output TI ADS79xx GPIO Levels On DO15-12 When DI04 Is Set
    Create Machine With TI ADS79xx
    Send ADS79xx Frame            0x40  0x03
    # Manual mode, DI11, DI04 (GPIO data on DO15-12), GPIO0 high
    Send ADS79xx Frame            0x18  0x11
    # The setting applies from the next sample, which is output a frame later:
    # this frame still carries the channel address (0), the next one GPIO0
    ${b}=                         Send ADS79xx Frame  0x00  0x00
    Should Be Equal As Integers   ${b}  0x00
    ${b}=                         Send ADS79xx Frame  0x00  0x00
    Should Be Equal As Integers   ${b}  0x10

Should Hold LTC6812 SDO Low During PLADC Until The Conversion Ends
    Create Machine With LTC6812
    # ADCV, all cells, 7kHz mode (MD = 10): 1956 us; then PLADC
    Send LTC6812 Bytes            0x03  0x60  0xF4  0x6C
    Send LTC6812 Bytes            0x07  0x14  0xF3  0x6C
    LTC6812 SDO Should Read       0x00
    Execute Command               emulation RunFor "0.001"
    LTC6812 SDO Should Read       0x00
    Execute Command               emulation RunFor "0.001"
    LTC6812 SDO Should Read       0xFF

Should Take The LTC6812 Conversion Time Of The Selected ADC Mode
    Create Machine With LTC6812
    # ADCV, all cells, 27kHz mode (MD = 01): 937 us
    Send LTC6812 Bytes            0x02  0xE0  0x38  0x06
    Send LTC6812 Bytes            0x07  0x14  0xF3  0x6C
    LTC6812 SDO Should Read       0x00
    Execute Command               emulation RunFor "0.001"
    LTC6812 SDO Should Read       0xFF

Should Stall The CPU For An SPI Word When SpiTimingStallsCpu Is Set
    Create Machine With A Timed SPI Master  true
    Load One SPI Word Program
    ${n}=                         Instructions Executed In 100 us
    # 100 MIPS for 100 us, less the 10 us until the word is received
    Should Be Equal As Integers   ${n}  9000

Should Start A Back To Back SPI Word After The Previous Word's Delays
    Create Machine With A Timed SPI Master  true
    # ldr r0, [pc, #12]; movs r1, #0x55; str r1, [r0]; str r1, [r0];
    # 1: adds r2, #1; b 1b; nop; nop; .word TBUF00
    Execute Command               sysbus WriteDoubleWord 0x20000000 0x21554803
    Execute Command               sysbus WriteDoubleWord 0x20000004 0x60016001
    Execute Command               sysbus WriteDoubleWord 0x20000008 0xE7FD3201
    Execute Command               sysbus WriteDoubleWord 0x2000000C 0xBF00BF00
    Execute Command               sysbus WriteDoubleWord 0x20000010 0x48020280
    ${n}=                         Instructions Executed In 100 us
    # The second word starts when the first one's trailing and inter-word
    # delays end (14 us) and is received 10 us later: the CPU runs 76 us
    Should Be Equal As Integers   ${n}  7600

Should Raise The Transmit Buffer Interrupt When A Word Enters The Shifter
    Create Machine With A Timed SPI Master  false
    Execute Command               cpu IsHalted true
    # INPR.TBINP = 2; CCR: SSC mode + TBIEN
    Execute Command               sysbus WriteDoubleWord 0x48020218 0x20
    Count Pulses On USIC1_CH1 Service Request  2
    Execute Command               sysbus WriteDoubleWord 0x48020240 0x2001
    # Enabling TBIEN with TBUF empty raises nothing: it is an event
    Pulses Should Be              0
    Execute Command               sysbus WriteDoubleWord 0x48020280 0x55
    Pulses Should Be              1
    # The second word waits for the shifter: its 14 us word ends first
    Execute Command               sysbus WriteDoubleWord 0x48020280 0xAA
    Pulses Should Be              1
    Execute Command               emulation RunFor "0.000013"
    Pulses Should Be              1
    Execute Command               emulation RunFor "0.000002"
    Pulses Should Be              2

Should Pulse A Service Request On An FMR SIO Write
    Create Machine With A Timed SPI Master  false
    Execute Command               cpu IsHalted true
    Count Pulses On USIC1_CH1 Service Request  1
    # FMR.SIO1 (bit 17) activates SR1
    Execute Command               sysbus WriteDoubleWord 0x48020268 0x20000
    Pulses Should Be              1
    Execute Command               sysbus WriteDoubleWord 0x48020268 0x10000
    Pulses Should Be              1

Should Not Stall The CPU For A Timed SPI Word By Default
    Create Machine With A Timed SPI Master  false
    Load One SPI Word Program
    ${n}=                         Instructions Executed In 100 us
    Should Be Equal As Integers   ${n}  10000

Should Read Back The LTC6812 Cell Inputs
    Create Machine With LTC6812
    ${n}=                         Execute Command  ${LTC6812} CellsPerDevice
    Should Be Equal As Integers   ${n.strip()}  15
    ${n}=                         Execute Command  ${LTC6812} NumberOfDevices
    Should Be Equal As Integers   ${n.strip()}  1
    # Reset: 3.6 V on every input
    ${mv}=                        Execute Command  ${LTC6812} GetCellMillivolts 15
    Should Be Equal As Integers   ${mv.strip()}  3600
    Execute Command               ${LTC6812} SetCellMillivolts 7 3456
    ${mv}=                        Execute Command  ${LTC6812} GetCellMillivolts 7
    Should Be Equal As Integers   ${mv.strip()}  3456
