*** Variables ***
${FLASH_REPL}                   SEPARATOR=\n
...                             usic: UART.XMC4XXX_UART @ sysbus 0x48020000
...                             mem: Memory.MappedMemory @ sysbus 0x60000000
...                             ${SPACE*4}size: 0x1000000
...                             flash: SPI.Winbond_W25Q @ usic
...                             ${SPACE*4}underlyingMemory: mem

*** Keywords ***
Create Machine With Flash
    [Arguments]                   ${timing}=${EMPTY}
    Execute Command               mach create
    Execute Command               machine LoadPlatformDescriptionFromString """${FLASH_REPL}\n${timing}"""
    # Drive the device the way an SPI controller does, through ISPIPeripheral
    Execute Command               python "from Antmicro.Renode.Peripherals.SPI import ISPIPeripheral; flash = self.Machine['sysbus.usic.flash']; xfer = lambda bs: [ISPIPeripheral.Transmit(flash, b) for b in bs] + [ISPIPeripheral.FinishTransmission(flash)]"

Transfer
    [Arguments]                   @{bytes}
    ${list}=                      Catenate  SEPARATOR=,  @{bytes}
    ${out}=                       Execute Command  python "print(xfer([${list}])[:-1])"
    RETURN                        ${out.strip()}

Status Should Be
    [Arguments]                   ${expected}
    ${out}=                       Transfer  0x05  0x00
    Should Be Equal               ${out}  [0, ${expected}]

*** Test Cases ***
Should Be Busy For The Page Program Time And Ignore Reads Meanwhile
    Create Machine With Flash     ${SPACE*4}PageProgramMicroseconds: 400
    Transfer                      0x06
    Transfer                      0x02  0x00  0x01  0x00  0xA5
    # WIP set; the write enable latch cleared at the end of the program
    Status Should Be              1
    # A read while busy is ignored: the device does not drive data
    ${out}=                       Transfer  0x03  0x00  0x01  0x00  0x00
    Should Be Equal               ${out}  [255, 255, 255, 255, 255]
    Execute Command               emulation RunFor "0.00039"
    Status Should Be              1
    Execute Command               emulation RunFor "0.00002"
    Status Should Be              0
    ${out}=                       Transfer  0x03  0x00  0x01  0x00  0x00
    Should Be Equal               ${out}  [0, 0, 0, 0, 165]

Should Time A Short Program By Its Bytes
    Create Machine With Flash     ${SPACE*4}PageProgramMicroseconds: 400\n${SPACE*4}ByteProgramFirstMicroseconds: 30\n${SPACE*4}ByteProgramNextMicroseconds: 2.5
    Transfer                      0x06
    # 10 bytes: 30 + 9 * 2.5 = 52.5 us, rounded up to 53
    Transfer                      0x02  0x00  0x02  0x00  0x01  0x02  0x03  0x04  0x05  0x06  0x07  0x08  0x09  0x0A
    Execute Command               emulation RunFor "0.00005"
    Status Should Be              1
    Execute Command               emulation RunFor "0.000004"
    Status Should Be              0

Should Be Busy For The Sector Erase Time
    Create Machine With Flash     ${SPACE*4}SectorEraseMicroseconds: 45000
    Transfer                      0x06
    Transfer                      0x20  0x00  0x10  0x00
    Status Should Be              1
    # A write enable while busy is ignored too
    Transfer                      0x06
    Status Should Be              1
    Execute Command               emulation RunFor "0.044"
    Status Should Be              1
    Execute Command               emulation RunFor "0.002"
    Status Should Be              0

Should Complete Instantly With No Timing Configured
    Create Machine With Flash
    Transfer                      0x06
    Transfer                      0x02  0x00  0x01  0x00  0x5A
    Status Should Be              0
    ${out}=                       Transfer  0x03  0x00  0x01  0x00  0x00
    Should Be Equal               ${out}  [0, 0, 0, 0, 90]
