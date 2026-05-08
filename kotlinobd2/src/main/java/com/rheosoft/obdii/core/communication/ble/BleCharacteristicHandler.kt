package com.rheosoft.obdii.core.communication.ble

class BleCharacteristicHandler(
    private val processor: BleMessageProcessor,
) {
    private val readUuidHints = setOf(
        "FFF1",
        "2AF0",
        "FFC1",
        "6E400003B5A3F393E0A9E50E24DCCA9E",
    )
    private val writeUuidHints = setOf(
        "FFF2",
        "2AF1",
        "FFC2",
        "6E400002B5A3F393E0A9E50E24DCCA9E",
    )
    private val readWriteUuidHints = setOf(
        "FFE1",
        "BEF8D6C99C214C9EB632BD58C1009F9F",
    )

    var readCharacteristic: BleCharacteristic? = null
        private set
    var writeCharacteristic: BleCharacteristic? = null
        private set

    val isReady: Boolean
        get() = readCharacteristic != null && writeCharacteristic != null

    fun setupCharacteristics(characteristics: List<BleCharacteristic>) {
        for (ch in characteristics) {
            assignCharacteristic(ch, normalizeUuid(ch.uuid))
        }
    }

    private fun assignCharacteristic(ch: BleCharacteristic, normalizedUuid: String) {
        when {
            normalizedUuid in readWriteUuidHints -> assignReadWriteHint(ch)
            normalizedUuid in readUuidHints -> assignRead(ch)
            normalizedUuid in writeUuidHints -> assignWrite(ch)
            else -> assignFallback(ch)
        }
    }

    private fun assignReadWriteHint(ch: BleCharacteristic) {
        assignRead(ch)
        assignWrite(ch)
        if (readCharacteristic == null) readCharacteristic = ch
        if (writeCharacteristic == null) writeCharacteristic = ch
    }

    private fun assignFallback(ch: BleCharacteristic) {
        if (readCharacteristic == null) assignRead(ch)
        if (writeCharacteristic == null) assignWrite(ch)
        if (readCharacteristic == null && writeCharacteristic == null && ch.canRead && ch.canWrite) {
            readCharacteristic = ch
            writeCharacteristic = ch
        }
    }

    private fun assignRead(ch: BleCharacteristic) {
        if (ch.canRead || ch.canNotify) readCharacteristic = ch
    }

    private fun assignWrite(ch: BleCharacteristic) {
        if (ch.canWrite) writeCharacteristic = ch
    }

    fun handleUpdatedValue(data: ByteArray) {
        processor.processReceivedData(data)
    }

    fun reset() {
        readCharacteristic = null
        writeCharacteristic = null
        processor.reset()
    }

    private fun normalizeUuid(raw: String): String {
        val uuid = raw.replace("-", "").uppercase()
        return if (uuid.length == 32 &&
            uuid.startsWith("0000") &&
            uuid.endsWith("00001000800000805F9B34FB")
        ) {
            uuid.substring(4, 8)
        } else {
            uuid
        }
    }
}
