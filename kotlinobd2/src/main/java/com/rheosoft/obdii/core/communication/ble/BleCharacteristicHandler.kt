package com.rheosoft.obdii.core.communication.ble

class BleCharacteristicHandler(
    private val processor: BleMessageProcessor,
) {
    var readCharacteristic: BleCharacteristic? = null
        private set
    var writeCharacteristic: BleCharacteristic? = null
        private set

    val isReady: Boolean
        get() = readCharacteristic != null && writeCharacteristic != null

    fun setupCharacteristics(characteristics: List<BleCharacteristic>) {
        for (ch in characteristics) {
            when (normalizeUuid(ch.uuid)) {
                "FFE1" -> {
                    if (ch.canWrite) writeCharacteristic = ch
                    if (ch.canRead || ch.canNotify) readCharacteristic = ch
                    if (readCharacteristic == null) readCharacteristic = ch
                    if (writeCharacteristic == null) writeCharacteristic = ch
                }
                "FFF1", "2AF0" -> if (ch.canRead || ch.canNotify) readCharacteristic = ch
                "FFF2", "2AF1" -> if (ch.canWrite) writeCharacteristic = ch
                "FFC1" -> if (ch.canRead || ch.canNotify) readCharacteristic = ch
                "FFC2" -> if (ch.canWrite) writeCharacteristic = ch
                "6E400002B5A3F393E0A9E50E24DCCA9E" -> if (ch.canWrite) writeCharacteristic = ch
                "6E400003B5A3F393E0A9E50E24DCCA9E" -> if (ch.canRead || ch.canNotify) readCharacteristic = ch
                // Some vLink adapters expose a proprietary RW+notify channel on this UUID.
                "BEF8D6C99C214C9EB632BD58C1009F9F" -> {
                    if (ch.canRead || ch.canNotify) readCharacteristic = ch
                    if (ch.canWrite) writeCharacteristic = ch
                }
                else -> {
                    if (readCharacteristic == null && (ch.canRead || ch.canNotify)) readCharacteristic = ch
                    if (writeCharacteristic == null && ch.canWrite) writeCharacteristic = ch
                    if (readCharacteristic == null && writeCharacteristic == null && ch.canRead && ch.canWrite) {
                        // Swift parity fallback: one characteristic can be both paths.
                        readCharacteristic = ch
                        writeCharacteristic = ch
                    }
                }
            }
        }
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
