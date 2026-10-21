*** Settings ***
Library                         String

*** Variables ***
${PLATFORM}                     @platforms/cpus/mc9s12p128.repl
# The CPU sees fixed page 0x0F at 0xC000-0xFFFF and the PPAGE-selected page at
# 0x8000-0xBFFF; the flash contents live at global addresses (page << 14).
${CODE}                         0x3C000
${RESET_VECTOR}                 0x3FFFE
${TIMER_CH0_VECTOR}             0x3FFEE

*** Keywords ***
Write Bytes
    [Arguments]                 ${address}  ${hex}
    @{bytes}=                   Split String  ${hex}
    FOR  ${i}  ${byte}  IN ENUMERATE  @{bytes}
        ${a}=                   Evaluate  ${address} + ${i}
        Execute Command         sysbus WriteByte ${a} 0x${byte}
    END

Create Machine With Program
    [Arguments]                 ${program}
    Execute Command             mach create
    Execute Command             machine LoadPlatformDescription ${PLATFORM}
    Write Bytes                 ${CODE}  ${program}
    Write Bytes                 ${RESET_VECTOR}  C0 00
    Execute Command             cpu Reset

Byte Should Be
    [Arguments]                 ${address}  ${expected}
    ${value}=                   Execute Command  sysbus ReadByte ${address}
    Should Be Equal As Integers  ${value}  ${expected}

*** Test Cases ***
Should Run From The Reset Vector
    # C000 LDS #$3F00; LDAA #$12; LDAB #$34; STD $2000; LDX #5
    # C00D INC $2002; DBNE X,C00D; BRA *
    Create Machine With Program  CF 3F 00 86 12 C6 34 7C 20 00 CE 00 05 72 20 02 04 35 FA 20 FE
    Execute Command             emulation RunFor "0.001"

    Byte Should Be              0x2000  0x12
    Byte Should Be              0x2001  0x34
    Byte Should Be              0x2002  5
    ${pc}=                      Execute Command  cpu PC
    Should Be Equal As Integers  ${pc}  0xC013

Should Read The Paged Window Selected By PPAGE
    # MOVB #8,PPAGE; LDAA $8123; STAA $2000; MOVB #9,PPAGE; LDAA $8123; STAA $2001; BRA *
    Create Machine With Program  18 0B 08 00 30 B6 81 23 7A 20 00 18 0B 09 00 30 B6 81 23 7A 20 01 20 FE
    Write Bytes                 0x20123  A5
    Write Bytes                 0x24123  5A
    Execute Command             emulation RunFor "0.001"

    Byte Should Be              0x2000  0xA5
    Byte Should Be              0x2001  0x5A

Should Call And Return Across Pages
    # C000 LDS #$3F00; MOVB #8,PPAGE; CALL $8000,$0A; LDAA PPAGE; STAA $2003; BRA *
    Create Machine With Program  CF 3F 00 18 0B 08 00 30 4A 80 00 0A B6 00 30 7A 20 03 20 FE
    # Page 0x0A, $8000: LDAA #$77; STAA $2002; RTC
    Write Bytes                 0x28000  86 77 7A 20 02 0A
    Execute Command             emulation RunFor "0.001"

    Byte Should Be              0x2002  0x77
    Byte Should Be              0x2003  0x08

Should Fire Timer Output Compare Interrupt
    # C000 LDS #$3F00; MOVB #1,TIOS; MOVB #1,TIE; LDD #$0100; STD TC0
    # C013 MOVB #$80,TSCR1; CLI; BRA *
    # C01C ISR: INC $2006; MOVB #1,TFLG1; RTI
    Create Machine With Program  CF 3F 00 18 0B 01 00 40 18 0B 01 00 4C CC 01 00 7C 00 50 18 0B 80 00 46 10 EF 20 FE 72 20 06 18 0B 01 00 4E 0B
    Write Bytes                 ${TIMER_CH0_VECTOR}  C0 1C
    Execute Command             emulation RunFor "0.0005"

    # TCNT counts one per instruction, so channel 0 matches once in 50k instructions
    Byte Should Be              0x2006  1

Should Not Count With The Timer Disabled
    # Same as above without setting TSCR1.TEN
    Create Machine With Program  CF 3F 00 18 0B 01 00 40 18 0B 01 00 4C CC 01 00 7C 00 50 01 01 01 01 01 10 EF 20 FE 72 20 06 18 0B 01 00 4E 0B
    Write Bytes                 ${TIMER_CH0_VECTOR}  C0 1C
    Execute Command             emulation RunFor "0.0005"

    Byte Should Be              0x2006  0

Should Convert Analog Channels Set From The Monitor
    # MOVB #$13,ATDCTL5 (MULT, channels 3..); LDD ATDDR0; STD $2008; LDD ATDDR1; STD $200A; BRA *
    Create Machine With Program  18 0B 13 00 75 FC 00 80 7C 20 08 FC 00 82 7C 20 0A 20 FE
    Execute Command             cpu SetAnalogValue 3 0x1230
    Execute Command             cpu SetAnalogValue 4 0x4560
    Execute Command             emulation RunFor "0.001"

    Byte Should Be              0x2008  0x12
    Byte Should Be              0x2009  0x30
    Byte Should Be              0x200A  0x45
    Byte Should Be              0x200B  0x60
